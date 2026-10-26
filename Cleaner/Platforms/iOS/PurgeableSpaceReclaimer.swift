#if os(iOS)
import Darwin
import Foundation
import Synchronization
import UIKit

/// Pide a iOS que vacíe el espacio purgable («Datos del sistema»).
///
/// iOS no permite a ninguna app borrar cachés de otras apps ni del sistema. Lo que sí hace
/// el propio iOS es purgarlas cuando una app pide espacio que no hay: cachés de apps,
/// archivos temporales, cachés de streaming, restos de actualizaciones y, con «Optimizar
/// almacenamiento» activado, los originales de Fotos que ya están en iCloud.
///
/// Es el mismo mecanismo que el conocido truco de «alquilar una película más grande que el
/// espacio libre», hecho de forma controlada y por oleadas:
/// 1. Se llena el espacio libre con un archivo de relleno hasta que iOS rechaza la escritura
///    (`ENOSPC`). Cada petición rechazada hace que iOS purgue para atenderla.
/// 2. Con el disco lleno se sigue pidiendo espacio cada poco: lo que iOS libera se ocupa al
///    momento, así la presión no baja y iOS pasa a purgar con más urgencia.
/// 3. Cuando iOS deja de liberar, se borra el relleno y se repite. Igual que con el truco de
///    la película, cada intento suele liberar algo más, hasta que deja de dar fruto.
///
/// El archivo de relleno se borra siempre: al terminar, al cancelar, si la app pasa a
/// segundo plano y, si la app se cerrase a la fuerza, en el siguiente arranque.
nonisolated enum PurgeableSpaceReclaimer {
    struct Progress: Sendable {
        /// Oleada en curso (empieza en 1).
        let wave: Int
        /// Bytes ocupados por el archivo de relleno.
        let reservedBytes: Int64
        /// Espacio libre que queda.
        let availableBytes: Int64
        /// Bytes que iOS ha liberado en total hasta ahora (aproximado).
        let purgedBytes: Int64
        /// `true` en cuanto el disco se ha llenado en esta oleada (iOS ya debería estar purgando).
        let reachedFull: Bool
    }

    struct Outcome: Sendable {
        /// Espacio libre ganado de verdad, medido con el relleno ya borrado.
        let freedBytes: Int64
        let waves: Int
        /// `false` si se detuvo antes de tiempo (cancelación o la app pasó a segundo plano).
        let completed: Bool
    }

    enum ReclaimError: LocalizedError {
        case cannotCreateFile(Int32)

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile(let code):
                "No se pudo crear el archivo temporal (\(String(cString: strerror(code))))."
            }
        }
    }

    /// Tamaño máximo de cada petición de espacio.
    static let chunk: Int64 = 512 * 1024 * 1024
    /// Petición mínima; si ni esto cabe, el disco está lleno del todo.
    static let minimumChunk: Int64 = 4 * 1024 * 1024
    /// Oleadas como máximo. Cada una vuelve a apretar a iOS desde cero.
    static let maximumWaves = 4
    /// Una oleada que libera menos que esto indica que a iOS ya no le queda nada que purgar.
    static let worthwhileWave: Int64 = 200 * 1024 * 1024
    /// Tras llenar el disco, si iOS no libera nada durante este tiempo, la oleada termina.
    /// `deleted` tarda en reaccionar: con menos de ~20 s se cortaba antes de que empezase.
    static let stallTimeout: Duration = .seconds(25)
    /// Duración máxima de una oleada y de toda la purga.
    static let waveTimeout: Duration = .seconds(120)
    static let totalTimeout: Duration = .seconds(300)

    static var reservationURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "MaCleaner-reserva-espacio.tmp")
    }

    /// Se activa al pasar la app a segundo plano: nunca se deja el disco lleno sin vigilancia.
    private static let abortFlag = Mutex(false)

    /// Detiene la purga en curso y borra el relleno al instante. Seguro de llamar siempre.
    static func abortIfRunning() {
        abortFlag.withLock { $0 = true }
    }

    private static var shouldStop: Bool {
        Task.isCancelled || abortFlag.withLock { $0 }
    }

    /// Borra un archivo de relleno que haya quedado si la app se cerró a mitad del proceso.
    static func removeLeftoverReservation() {
        try? FileManager.default.removeItem(at: reservationURL)
    }

    /// Ejecuta la purga hasta liberar `target` bytes (o todo lo posible si es `nil`).
    @concurrent
    @discardableResult
    static func run(target: Int64?, onProgress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> Outcome {
        abortFlag.withLock { $0 = false }
        removeLeftoverReservation()
        // Que la pantalla no se bloquee: al bloquearse, la app pasa a segundo plano y se detiene.
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }

        let initialAvailable = available()
        let clock = ContinuousClock()
        let deadline = clock.now + totalTimeout
        var wave = 0
        var completed = true

        do {
            while wave < maximumWaves {
                if shouldStop { completed = false; break }
                wave += 1
                let before = available()
                try await runWave(number: wave, deadline: deadline, initialAvailable: initialAvailable, target: target, onProgress: onProgress)
                // El relleno ya está borrado: se deja que iOS contabilice lo liberado.
                try? await Task.sleep(for: .seconds(2))
                let gained = available() - before
                let total = available() - initialAvailable

                if let target, total >= target { break }
                if gained < worthwhileWave || clock.now >= deadline { break }
            }
        } catch {
            await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
            throw error
        }

        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
        if shouldStop { completed = false }
        return Outcome(freedBytes: max(0, available() - initialAvailable), waves: wave, completed: completed)
    }

    /// Una oleada: llena el disco, mantiene la presión mientras iOS purgue y borra el relleno.
    private static func runWave(
        number: Int,
        deadline: ContinuousClock.Instant,
        initialAvailable: Int64,
        target: Int64?,
        onProgress: @Sendable (Progress) -> Void
    ) async throws {
        let path = reservationURL.path
        let descriptor = open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ReclaimError.cannotCreateFile(errno) }
        defer {
            close(descriptor)
            unlink(path)
        }

        var filler = Filler(descriptor: descriptor)
        let clock = ContinuousClock()
        let waveDeadline = min(deadline, clock.now + waveTimeout)
        var lastGrowth = clock.now
        var reachedFull = false
        // Tamaño de la siguiente petición: se reduce a la mitad con cada rechazo para absorber
        // hasta el último hueco, y vuelve al máximo en cuanto iOS libera algo.
        var request = chunk

        while clock.now < waveDeadline, !shouldStop {
            // Se pide al menos un tramo aunque `statfs` diga que no cabe: la petición rechazada
            // es justo lo que hace que iOS purgue.
            let room = available()
            switch filler.grow(by: max(request, min(chunk, room))) {
            case .grew:
                lastGrowth = clock.now
                request = chunk
            case .full:
                reachedFull = true
                request = max(minimumChunk, request / 2)
            }

            let purged = max(0, filler.size + available() - initialAvailable)
            onProgress(Progress(wave: number, reservedBytes: filler.size, availableBytes: available(), purgedBytes: purged, reachedFull: reachedFull))

            // Al llegar al objetivo se para: así el almacenamiento está lleno el menor tiempo posible.
            if let target, purged >= target { break }
            if reachedFull, clock.now - lastGrowth > stallTimeout { break }
            // Mientras haya espacio se llena deprisa; con el disco lleno se insiste cada poco.
            try? await Task.sleep(for: reachedFull ? .milliseconds(250) : .milliseconds(20))
        }
    }

    /// Espacio libre real según el sistema de archivos (`statfs`), sin cachés de `URL`.
    static func available() -> Int64 {
        var info = statfs()
        guard statfs(NSHomeDirectory(), &info) == 0 else { return 0 }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
    }

    /// Hace crecer el archivo de relleno. Primero con `F_PREALLOCATE` (asigna bloques sin
    /// escribir datos, no desgasta el almacenamiento); si iOS no lo admite, escribiendo ceros.
    private struct Filler {
        enum Outcome { case grew, full }

        let descriptor: Int32
        private(set) var size: Int64 = 0
        private var usesWrites = false
        private static let zeros = [UInt8](repeating: 0, count: 4 * 1024 * 1024)

        init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        mutating func grow(by bytes: Int64) -> Outcome {
            if !usesWrites {
                // Todo o nada: una petición que no cabe entera se rechaza y obliga a purgar.
                var store = fstore_t(
                    fst_flags: UInt32(F_ALLOCATEALL),
                    fst_posmode: F_PEOFPOSMODE,
                    fst_offset: 0,
                    fst_length: off_t(bytes),
                    fst_bytesalloc: 0
                )
                if fcntl(descriptor, F_PREALLOCATE, &store) != -1 {
                    size += Int64(store.fst_bytesalloc)
                    // Fija el tamaño para que los bloques reservados no se suelten.
                    ftruncate(descriptor, off_t(size))
                    return .grew
                }
                if errno == ENOSPC { return .full }
                // Sin soporte de preasignación: se pasa a escribir ceros.
                usesWrites = true
            }
            return writeZeros(bytes)
        }

        private mutating func writeZeros(_ bytes: Int64) -> Outcome {
            var remaining = bytes
            var wroteAnything = false
            while remaining > 0 {
                let count = Int(min(remaining, Int64(Self.zeros.count)))
                let written = Self.zeros.withUnsafeBytes { buffer in
                    pwrite(descriptor, buffer.baseAddress, count, off_t(size))
                }
                // Cualquier fallo de escritura (normalmente ENOSPC) significa que ya no cabe más.
                if written <= 0 { return wroteAnything ? .grew : .full }
                wroteAnything = true
                size += Int64(written)
                remaining -= Int64(written)
            }
            return .grew
        }
    }
}
#endif
