#if os(macOS)
import Darwin
import Foundation

nonisolated enum FullDiskAccessStatus: Sendable, Equatable {
    case granted
    case denied
    /// No se pudo determinar (por ejemplo, la base de datos no existe).
    case undetermined
}

/// Comprueba si el usuario ha concedido "Acceso total al disco" (TCC) a esta app.
///
/// No existe una API pública para consultarlo. La técnica estándar es una lectura pasiva
/// de la base de datos TCC del usuario: está protegida por TCC, así que solo se puede
/// abrir con acceso total al disco. Solo se lee 1 byte y nunca se interpreta el contenido.
nonisolated enum FullDiskAccessProbe {
    static var tccDatabasePath: String {
        NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
    }

    static func check() -> FullDiskAccessStatus {
        let descriptor = open(tccDatabasePath, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case EPERM, EACCES: return .denied
            default: return .undetermined
            }
        }
        defer { close(descriptor) }

        var byte: UInt8 = 0
        return read(descriptor, &byte, 1) >= 0 ? .granted : .denied
    }

    /// Abre Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco.
    static var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }
}
#endif
