#if os(macOS)
import Foundation

/// Constantes compartidas entre la app principal y el demonio privilegiado.
/// Este archivo debe pertenecer a los targets `MaCleaner` y `CleanerHelper`.
nonisolated enum HelperConstants {
    static let appBundleIdentifier = "com.tuempresa.Cleaner"
    static let helperBundleIdentifier = "com.tuempresa.Cleaner.Helper"

    /// Versión del demonio que espera esta versión de la app. Súbela cada vez que cambie
    /// `HelperProtocol` o `PrivilegedService`: la app ofrecerá reinstalarlo.
    static let helperVersion = "1.1.0"

    /// Debe coincidir con `MachServices` del launchd.plist.
    static let machServiceName = "com.tuempresa.Cleaner.Helper"

    /// Nombre del plist en `MaCleaner.app/Contents/Library/LaunchDaemons/`.
    static let daemonPlistName = "com.tuempresa.Cleaner.Helper.plist"

    /// Únicos directorios dentro de los cuales el demonio acepta borrar.
    /// Es una lista blanca de defensa en profundidad: aunque el cliente esté firmado,
    /// el demonio nunca borra rutas arbitrarias.
    static let privilegedRoots = [
        "/Library/Caches",
        "/Library/Logs",
        "/private/var/log",
    ]

    /// Carpetas de agentes y demonios de las que el demonio acepta borrar plists de
    /// terceros (solo hijos directos con extensión `.plist`, nunca `com.apple.*`).
    static let launchItemRoots = [
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
    ]
}
#endif
