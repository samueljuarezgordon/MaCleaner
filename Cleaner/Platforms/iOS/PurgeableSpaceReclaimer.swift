#if os(iOS)
import Darwin
import Foundation

/// Pide a iOS que vacíe el espacio purgable («Datos del sistema»).
///
/// iOS no permite a ninguna app borrar cachés de otras apps ni del sistema. Lo que sí hace
/// el propio iOS es purgarlas cuando el almacenamiento se llena: cachés de apps, archivos
/// temporales, cachés de streaming y, con «Optimizar almacenamiento» activado, los
/// originales de Fotos en iCloud que ya están en la nube.
///
/// Técnica del «archivo de relleno»: se ocupa el espacio libre por tramos dentro del propio
/// contenedor de la app hasta que el disco se llena (`ENOSPC`). Ese es justo el estado que
/// hace que iOS purgue. Cuando iOS libera espacio, se ocupa también, hasta que deja de
/// liberar. Al terminar, el archivo se borra de inmediato.
nonisolated enum PurgeableSpaceReclaimer {
    struct Progress: Sendable {
        /// Bytes ocupados por el archivo de relleno.
        let reservedBytes: Int64
        /// Espacio libre que queda.
        let availableBytes: Int64
        /// Bytes que iOS ha liberado hasta ahora (aproximado).
        let purgedBytes: Int64
        /// `true` en cuanto el disco se ha llenado (iOS ya debería estar purgando).
        let reachedFull: Bool
    }

    enum ReclaimError: LocalizedError {
        case cannotCreateFile(Int32)
        case nothingToFill

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile(let code):
                "No se pudo crear el archivo temporal (\(String(cString: strerror(code))))."
            case .nothingToFill:
                "El almacenamiento ya está prácticamente lleno: iOS debería estar purgando por su cuenta. Prueba de nuevo dentro de unos minutos."
            }
        }
    }

    /// Espacio que se intenta dejar libre para que el sistema siga respondiendo.
    static let safetyFloor: Int64 = 300 * 1024 * 1024
    /// Tamaño de cada tramo. Tramos pequeños: si iOS rechaza uno, el siguiente sigue intentándolo.
    static let chunk: Int64 = 256 * 1024 * 1024
    /// Tramo mínimo; por debajo de esto el disco se considera lleno.
    static let minimumChunk: Int64 = 16 * 1024 * 1024
    static let timeout: Duration = .seconds(90)
    /// Tras llenar el disco, si iOS no libera nada durante este tiempo, se da por terminado.
    static let stallTimeout: Duration = .seconds(12)

    static var reservationURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "MaCleaner-reserva-espacio.tmp")
    }

    /// Borra un archivo de relleno que haya quedado si la app se cerró a mitad del proceso.
    static func removeLeftoverReservation() {
        try? FileManager.default.removeItem(at: reservationURL)
    }

    /// Ejecuta la purga hasta liberar `target` bytes (o todo lo posible si es `nil`).
    /// El archivo de relleno se borra siempre: al terminar, al cancelarse o si falla.
    @concurrent
    static func run(target: Int64?, onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        removeLeftoverReservation()
        let path = reservationURL.path
        let descriptor = open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ReclaimError.cannotCreateFile(errno) }
        defer {
            close(descriptor)
            unlink(path)
        }

        var filler = Filler(descriptor: descriptor)
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var lastGrowth = clock.now
        var reachedFull = false
        let initialAvailable = available()
        guard initialAvailable - safetyFloor >= minimumChunk else { throw ReclaimError.nothingToFill }

        while clock.now < deadline, !Task.isCancelled {
            let room = available() - safetyFloor
            if room >= minimumChunk {
                switch filler.grow(by: min(chunk, room)) {
                case .grew:
                    lastGrowth = clock.now
                case .full:
                    // El disco se ha llenado: es justo lo que hace que iOS purgue.
                    reachedFull = true
                }
            } else {
                reachedFull = true
            }

            let now = available()
            let purged = max(0, filler.size + now - initialAvailable)
            onProgress(Progress(reservedBytes: filler.size, availableBytes: now, purgedBytes: purged, reachedFull: reachedFull))

            // Al llegar al objetivo se para: así el almacenamiento está lleno el menor tiempo posible.
            if let target, purged >= target { break }
            if reachedFull, clock.now - lastGrowth > stallTimeout { break }
            // Mientras haya espacio se llena deprisa; con el disco lleno se espera a iOS.
            try? await Task.sleep(for: reachedFull ? .milliseconds(500) : .milliseconds(50))
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
            while remaining > 0 {
                let count = Int(min(remaining, Int64(Self.zeros.count)))
                let written = Self.zeros.withUnsafeBytes { buffer in
                    pwrite(descriptor, buffer.baseAddress, count, off_t(size))
                }
                // Cualquier fallo de escritura (normalmente ENOSPC) significa que ya no cabe más.
                if written <= 0 { return .full }
                size += Int64(written)
                remaining -= Int64(written)
            }
            return .grew
        }
    }
}
#endif
