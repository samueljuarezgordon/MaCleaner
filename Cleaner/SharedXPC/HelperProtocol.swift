#if os(macOS)
import Foundation

/// Interfaz XPC que exporta el demonio privilegiado.
///
/// `nonisolated` evita que el aislamiento por defecto en `MainActor` del módulo se aplique
/// al protocolo: NSXPCConnection invoca estos métodos en sus propias colas.
@objc(CleanerHelperProtocol)
nonisolated protocol HelperProtocol {
    /// Versión del demonio, para detectar instalaciones desactualizadas.
    func version(withReply reply: @escaping @Sendable (String) -> Void)

    /// Borra las rutas indicadas si están dentro de `HelperConstants.privilegedRoots`.
    /// Responde con las rutas eliminadas y los mensajes de error.
    func removeItems(atPaths paths: [String], withReply reply: @escaping @Sendable ([String], [String]) -> Void)

    /// Ejecuta `tmutil thinlocalsnapshots / 999999999999 4`.
    /// Responde con el código de salida y la salida combinada del comando.
    func thinLocalSnapshots(withReply reply: @escaping @Sendable (Int32, String) -> Void)

    /// Detiene y borra un agente o demonio de terceros de `HelperConstants.launchItemRoots`.
    /// La etiqueta se lee del propio plist; nunca se confía en la del cliente.
    /// Responde con si se borró y un mensaje.
    func removeLaunchItem(atPath path: String, withReply reply: @escaping @Sendable (Bool, String) -> Void)
}
#endif
