#if os(macOS)
import AppKit
import Foundation

/// Índice de apps instaladas y en ejecución. Permite saber a quién pertenece una carpeta de
/// `~/Library` y si su app está abierta.
nonisolated struct InstalledAppIndex: Sendable {
    /// A quién pertenece una carpeta con nombre de identificador de bundle.
    enum Ownership: Sendable, Equatable {
        case installed
        /// Copia que dejó una app al restablecerse o actualizarse (`com.app.id.reset-…`).
        case residualCopy(ofBundleIdentifier: String)
        /// No hay ninguna app con ese identificador, pero sí otra del mismo fabricante.
        case sameVendor(String)
        case orphan
    }

    /// Identificadores en minúsculas → nombre visible de la app.
    private let appNamesByIdentifier: [String: String]
    private let runningIdentifiers: Set<String>
    private let runningNames: Set<String>

    // MARK: - Construcción

    static func build() async -> InstalledAppIndex {
        let running = await MainActor.run {
            NSWorkspace.shared.runningApplications.map {
                RunningApp(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName)
            }
        }

        var names: [String: String] = [:]
        let home = NSHomeDirectory()
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            home + "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
        ]
        for root in roots {
            collectApps(in: root, depth: 2, into: &names)
        }

        return InstalledAppIndex(
            appNamesByIdentifier: names,
            runningIdentifiers: Set(running.compactMap { $0.bundleIdentifier?.lowercased() }),
            runningNames: Set(running.compactMap { $0.name.map(normalize) })
        )
    }

    private struct RunningApp: Sendable {
        let bundleIdentifier: String?
        let name: String?
    }

    /// Recorre una carpeta de apps. Entra en carpetas que no son apps (p. ej.
    /// `/Applications/Microsoft Office`) y también en las apps auxiliares que hay dentro de
    /// cada bundle (`Contents/Library/LoginItems`, `Contents/Helpers`).
    private static func collectApps(in directory: String, depth: Int, into names: inout [String: String]) {
        guard depth > 0, let entries = try? BulkDirectoryScanner().entries(in: directory) else { return }

        for entry in entries where entry.isDirectory {
            let path = directory + "/" + entry.name
            if entry.name.hasSuffix(".app") {
                if let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist"),
                   let identifier = info["CFBundleIdentifier"] as? String {
                    let name = (info["CFBundleDisplayName"] as? String)
                        ?? (info["CFBundleName"] as? String)
                        ?? String(entry.name.dropLast(4))
                    names[identifier.lowercased()] = name
                }
                for nested in ["/Contents/Library/LoginItems", "/Contents/Helpers", "/Contents/Applications"] {
                    collectApps(in: path + nested, depth: 1, into: &names)
                }
            } else if !entry.name.hasPrefix(".") {
                collectApps(in: path, depth: depth - 1, into: &names)
            }
        }
    }

    static func normalize(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    // MARK: - Consultas

    /// Indica si `name` tiene forma de identificador de bundle (`com.empresa.app`).
    static func looksLikeBundleIdentifier(_ name: String) -> Bool {
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3, !name.contains(" "),
              let first = components.first, (2...6).contains(first.count),
              first.allSatisfy({ $0.isLetter && $0.isLowercase }) else { return false }
        return components.allSatisfy { !$0.isEmpty }
    }

    func displayName(forBundleIdentifier identifier: String) -> String? {
        appNamesByIdentifier[identifier.lowercased()]
    }

    /// Nombre de alguna app instalada del mismo fabricante (`com.docker.socket` → Docker).
    func appName(sharingVendorWith identifier: String) -> String? {
        let parts = identifier.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let vendor = parts.prefix(2).joined(separator: ".") + "."
        return appNamesByIdentifier.first { $0.key.hasPrefix(vendor) }?.value
    }

    func ownership(ofBundleLikeName name: String) -> Ownership {
        let lower = name.lowercased()
        if appNamesByIdentifier[lower] != nil { return .installed }

        for identifier in appNamesByIdentifier.keys where lower.hasPrefix(identifier + ".") {
            let suffix = lower.dropFirst(identifier.count + 1)
            if Self.isResidualSuffix(suffix) {
                return .residualCopy(ofBundleIdentifier: identifier)
            }
            // Extensiones y apps auxiliares (com.app.id.ShareExtension…).
            return .installed
        }

        // Carpeta con un identificador más corto que el de la app (com.docker para com.docker.docker).
        if appNamesByIdentifier.keys.contains(where: { $0.hasPrefix(lower + ".") }) {
            return .installed
        }

        let vendor = lower.split(separator: ".").prefix(2).joined(separator: ".")
        if appNamesByIdentifier.keys.contains(where: { $0.hasPrefix(vendor + ".") }) {
            return .sameVendor(vendor)
        }
        return .orphan
    }

    /// Sufijos típicos de copias de seguridad o restablecimiento.
    private static func isResidualSuffix(_ suffix: Substring) -> Bool {
        let markers = ["reset", "backup", "bak", "old", "copy", "previous"]
        if markers.contains(where: { suffix.hasPrefix($0) }) { return true }
        // Marca de tiempo larga: com.app.id.1784145972095
        return suffix.prefix(while: \.isNumber).count >= 10
    }

    /// Indica si la app dueña de una carpeta (por identificador o por nombre) está abierta.
    func isRunning(owner: String) -> Bool {
        runningIdentifiers.contains(owner.lowercased()) || runningNames.contains(Self.normalize(owner))
    }
}
#endif
