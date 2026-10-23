#if os(iOS)
import Darwin
import Foundation

/// Pide a iOS que vacíe el espacio purgable («Datos del sistema»).
///
/// iOS no permite a ninguna app borrar cachés de otras apps ni del sistema. Lo que sí hace
/// el propio iOS es purgarlas cuando el almacenamiento está casi lleno: cachés de apps,
/// archivos temporales, cachés de streaming y, con «Optimizar almacenamiento» activado, los
/// originales de Fotos en iCloud que ya están en la nube.
///
/// Esto reserva temporalmente el espacio libre dentro del propio contenedor de la app
/// (`F_PREALLOCATE`: asigna bloques sin escribir datos ni desgastar el almacenamiento) para
/// que iOS vea el disco casi lleno y purgue. Después libera la reserva por completo.
nonisolated enum PurgeableSpaceReclaimer {
    struct Progress: Sendable {
        /// Bytes reservados ahora mismo.
        let reservedBytes: Int64
        /// Espacio libre que queda.
        let availableBytes: Int64
        /// Bytes que iOS ha liberado hasta ahora (aproximado).
        let purgedBytes: Int64
    }

    enum ReclaimError: LocalizedError {
        case cannotCreateFile(Int32)
        case unsupported(Int32)

        var errorDescription: String? {
            switch self {
            case .cannotCreateFile(let code):
                "No se pudo crear el archivo temporal (\(String(cString: strerror(code))))."
            case .unsupported(let code):
                "iOS no permitió reservar espacio (\(String(cString: strerror(code))))."
            }
        }
    }

    /// Espacio que siempre se deja libre para que el resto del sistema siga funcionando.
    static let safetyFloor: Int64 = 700 * 1024 * 1024
    /// Cada paso reserva como mínimo esto; por debajo no merece la pena.
    static let minimumStep: Int64 = 128 * 1024 * 1024
    static let timeout: Duration = .seconds(60)
    /// Si iOS no libera nada durante este tiempo, se da por terminado.
    static let stallTimeout: Duration = .seconds(5)

    static var reservationURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "MaCleaner-reserva-espacio.tmp")
    }

    /// Borra una reserva que haya quedado si la app se cerró a mitad del proceso.
    static func removeLeftoverReservation() {
        try? FileManager.default.removeItem(at: reservationURL)
    }

    /// Ejecuta la purga. Libera siempre la reserva al terminar, al cancelarse o si falla.
    @concurrent
    static func run(onProgress: @escaping @Sendable (Progress) -> Void) async throws {
        removeLeftoverReservation()
        let path = reservationURL.path
        let descriptor = open(path, O_RDWR | O_CREAT | O_TRUNC | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw ReclaimError.cannotCreateFile(errno) }
        defer {
            close(descriptor)
            unlink(path)
        }

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var lastGrowth = clock.now
        var reserved: Int64 = 0
        let initialAvailable = available()

        while clock.now < deadline, !Task.isCancelled {
            let free = available()
            let room = free - safetyFloor
            if room >= minimumStep {
                var store = fstore_t(
                    fst_flags: UInt32(F_ALLOCATEALL),
                    fst_posmode: F_PEOFPOSMODE,
                    fst_offset: 0,
                    fst_length: off_t(room),
                    fst_bytesalloc: 0
                )
                if fcntl(descriptor, F_PREALLOCATE, &store) == -1 {
                    // La primera vez es un error real; después, el disco simplemente se llenó.
                    if reserved == 0 { throw ReclaimError.unsupported(errno) }
                } else {
                    reserved += Int64(store.fst_bytesalloc)
                    // Se fija el tamaño para que la reserva no se suelte antes de tiempo.
                    ftruncate(descriptor, off_t(reserved))
                    lastGrowth = clock.now
                }
            } else if clock.now - lastGrowth > stallTimeout {
                break
            }

            let now = available()
            onProgress(Progress(
                reservedBytes: reserved,
                availableBytes: now,
                purgedBytes: max(0, reserved + now - initialAvailable)
            ))
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Espacio libre real ahora mismo. Se crea una URL nueva cada vez porque `URL` guarda en
    /// caché los valores de recursos.
    static func available() -> Int64 {
        DiskUsage.current()?.availableBytes ?? 0
    }
}
#endif
