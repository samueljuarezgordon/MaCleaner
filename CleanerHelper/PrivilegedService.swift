import Darwin
import Foundation

/// Implementación de las operaciones privilegiadas. Se ejecuta como root.
nonisolated final class PrivilegedService: NSObject, HelperProtocol {
    static let version = HelperConstants.helperVersion

    private let clientRequirement: String

    init(clientRequirement: String) {
        self.clientRequirement = clientRequirement
    }

    // MARK: - HelperProtocol

    func version(withReply reply: @escaping @Sendable (String) -> Void) {
        IdleMonitor.shared.begin()
        defer { IdleMonitor.shared.end() }
        reply(Self.version)
    }

    func removeItems(atPaths paths: [String], withReply reply: @escaping @Sendable ([String], [String]) -> Void) {
        IdleMonitor.shared.begin()
        defer { IdleMonitor.shared.end() }
        guard callerIsTrusted() else {
            reply([], ["Cliente no autorizado"])
            return
        }

        var removed: [String] = []
        var failures: [String] = []
        for path in paths {
            guard let resolved = Self.resolveAllowedPath(path) else {
                failures.append("\(path): fuera de las rutas permitidas")
                continue
            }
            do {
                try FileManager.default.removeItem(atPath: resolved)
                removed.append(path)
            } catch {
                failures.append("\(path): \(error.localizedDescription)")
            }
        }
        reply(removed, failures)
    }

    func thinLocalSnapshots(withReply reply: @escaping @Sendable (Int32, String) -> Void) {
        guard callerIsTrusted() else {
            reply(-1, "Cliente no autorizado")
            return
        }

        // La operación sigue después de volver de este método: no puede cerrarse por inactividad.
        IdleMonitor.shared.begin()
        Task {
            defer { IdleMonitor.shared.end() }
            do {
                // Pide liberar hasta ~1 TB de espacio purgable con urgencia máxima (4),
                // lo que obliga a eliminar todas las instantáneas locales posibles.
                let output = try await ProcessRunner.run(
                    "/usr/bin/tmutil",
                    arguments: ["thinlocalsnapshots", "/", "999999999999", "4"]
                )
                reply(output.exitCode, output.output)
            } catch {
                reply(-1, error.localizedDescription)
            }
        }
    }

    func removeLaunchItem(atPath path: String, withReply reply: @escaping @Sendable (Bool, String) -> Void) {
        guard callerIsTrusted() else {
            reply(false, "Cliente no autorizado")
            return
        }
        guard let resolved = Self.resolveLaunchItemPath(path) else {
            reply(false, "\(path): fuera de las rutas permitidas")
            return
        }
        guard let plist = NSDictionary(contentsOfFile: resolved),
              let label = plist["Label"] as? String, !label.isEmpty else {
            reply(false, "\(path): no es un plist de launchd válido")
            return
        }
        guard !label.hasPrefix("com.apple.") else {
            reply(false, "\(label): los servicios de Apple no se pueden eliminar")
            return
        }

        IdleMonitor.shared.begin()
        Task {
            defer { IdleMonitor.shared.end() }
            // Los demonios viven en el dominio `system`; los agentes, en el de cada usuario
            // (la app los detiene antes de llamar aquí).
            if resolved.hasPrefix("/Library/LaunchDaemons/") {
                _ = try? await ProcessRunner.run("/bin/launchctl", arguments: ["bootout", "system/\(label)"])
            }
            do {
                try FileManager.default.removeItem(atPath: resolved)
                reply(true, "\(label) eliminado")
            } catch {
                reply(false, "\(label): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Seguridad

    /// Ruta canónica de un plist que sea hijo directo de `HelperConstants.launchItemRoots`.
    /// Rechaza enlaces simbólicos para que no se pueda redirigir el borrado.
    static func resolveLaunchItemPath(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard path.hasPrefix("/"), !url.pathComponents.contains(".."),
              url.pathExtension == "plist",
              let parent = canonicalPath(url.deletingLastPathComponent().path) else { return nil }

        let candidate = parent + "/" + url.lastPathComponent
        var info = stat()
        guard lstat(candidate, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }

        for root in HelperConstants.launchItemRoots {
            if let canonicalRoot = canonicalPath(root), parent == canonicalRoot {
                return candidate
            }
        }
        return nil
    }

    /// Revalida criptográficamente al cliente justo antes de cada operación destructiva.
    private func callerIsTrusted() -> Bool {
        guard let connection = NSXPCConnection.current() else { return false }
        return CodeSigningValidator.validate(connection, requirement: clientRequirement)
    }

    /// Devuelve la ruta canónica si está dentro de `HelperConstants.privilegedRoots`.
    ///
    /// Se resuelve con `realpath` el directorio padre, no el elemento final: si el elemento
    /// es un enlace simbólico, se borra el enlace y nunca su destino. Así un enlace colocado
    /// en `/Library/Caches` no puede redirigir el borrado a otra parte del disco.
    static func resolveAllowedPath(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard path.hasPrefix("/"),
              !url.pathComponents.contains(".."),
              !url.lastPathComponent.isEmpty,
              let parent = canonicalPath(url.deletingLastPathComponent().path) else {
            return nil
        }

        let candidate = parent + "/" + url.lastPathComponent
        for root in HelperConstants.privilegedRoots {
            guard let canonicalRoot = canonicalPath(root) else { continue }
            if candidate.hasPrefix(canonicalRoot + "/") {
                return candidate
            }
        }
        return nil
    }

    private static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
