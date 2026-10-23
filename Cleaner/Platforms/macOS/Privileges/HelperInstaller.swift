#if os(macOS)
import ServiceManagement

nonisolated enum HelperInstallationState: Sendable, Equatable {
    case notRegistered
    case requiresApproval
    case enabled
    /// El plist no está en `Contents/Library/LaunchDaemons` o el bundle está mal formado.
    case notFound
}

/// Registro del demonio con la API moderna `SMAppService` (macOS 13+).
///
/// A diferencia de `SMJobBless`, no copia el binario a `/Library/PrivilegedHelperTools`:
/// launchd ejecuta directamente el ejecutable firmado que hay dentro del bundle de la app,
/// así que la actualización de la app actualiza también el demonio.
enum HelperInstaller {
    private static var service: SMAppService {
        .daemon(plistName: HelperConstants.daemonPlistName)
    }

    static var state: HelperInstallationState {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    /// Registra el demonio. La primera vez, macOS lo deja en `.requiresApproval` hasta que el
    /// usuario lo activa en Ajustes del Sistema → General → Ítems de inicio.
    static func register() throws {
        try service.register()
    }

    static func unregister() async throws {
        try await service.unregister()
    }

    static func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
#endif
