#if os(macOS)
import CoreServices
import Foundation

/// Recolectores de aplicaciones y de elementos de inicio.
nonisolated extension MacScanCollectors {

    // MARK: - Aplicaciones

    /// Apps sin abrir en este tiempo se consideran poco usadas.
    static let unusedAppDays = 90
    /// Apps (con sus datos) a partir de este tamaño se consideran pesadas.
    static let largeAppThreshold: Int64 = 1_000_000_000

    private struct AppCandidate: Sendable {
        let path: String
        let name: String
        let identifier: String
        let version: String?
        let appBytes: TreeUsage
        let lastUsed: Date?
        let isAppStore: Bool
    }

    static func applications(_ context: MacScanContext) async throws -> [ScanItem] {
        let paths = appBundlePaths(context)

        // Paso 1: medir cada app y leer cuándo se usó por última vez.
        let candidates = try await withThrowingTaskGroup(of: AppCandidate?.self) { group in
            for path in paths {
                group.addTask { try await appCandidate(at: path, context: context) }
            }
            var result: [AppCandidate] = []
            for try await candidate in group {
                if let candidate { result.append(candidate) }
            }
            context.reportMetrics()
            return result
        }

        // Paso 2: solo para las poco usadas o pesadas, medir sus datos asociados.
        return try await withThrowingTaskGroup(of: ScanItem?.self) { group in
            for app in candidates {
                group.addTask { try await appItem(app, context: context) }
            }
            var items: [ScanItem] = []
            for try await item in group {
                if let item { items.append(item) }
            }
            return items
        }
    }

    /// Apps de `/Applications` y `~/Applications`, entrando un nivel en carpetas de fabricante.
    private static func appBundlePaths(_ context: MacScanContext) -> [String] {
        var paths: [String] = []
        for root in ["/Applications", context.home + "/Applications"] {
            for entry in context.entries(in: root, for: .unusedApps) where entry.isDirectory && !entry.name.hasPrefix(".") {
                let path = root + "/" + entry.name
                if entry.name.hasSuffix(".app") {
                    paths.append(path)
                } else {
                    paths += context.entries(in: path, for: .unusedApps)
                        .filter { $0.isDirectory && $0.name.hasSuffix(".app") }
                        .map { path + "/" + $0.name }
                }
            }
        }
        return paths
    }

    private static func appCandidate(at path: String, context: MacScanContext) async throws -> AppCandidate? {
        guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist"),
              let identifier = info["CFBundleIdentifier"] as? String,
              !identifier.hasPrefix("com.apple."),
              identifier != HelperConstants.appBundleIdentifier,
              // Los instaladores de macOS ya se tratan en Descargas.
              !(path as NSString).lastPathComponent.hasPrefix("Install macOS") else { return nil }

        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let usage = try await context.measure(.directory(path))
        return AppCandidate(
            path: path,
            name: name,
            identifier: identifier,
            version: info["CFBundleShortVersionString"] as? String,
            appBytes: usage,
            lastUsed: lastUsedDate(ofItemAt: path),
            isAppStore: access(path + "/Contents/_MASReceipt/receipt", F_OK) == 0
        )
    }

    private static func appItem(_ app: AppCandidate, context: MacScanContext) async throws -> ScanItem? {
        let maybeUnused = app.lastUsed.map { $0.isOlder(thanDays: unusedAppDays) } ?? true
        guard maybeUnused || app.appBytes.reclaimableBytes >= largeAppThreshold / 2 else { return nil }

        let related = relatedPaths(for: app, home: context.home)
        var dataBytes: Int64 = 0
        var dataAllocated: Int64 = 0
        var dataModified: Date?
        for path in related {
            let usage = try await usage(ofPath: path, context: context)
            dataBytes += usage.reclaimableBytes
            dataAllocated += usage.allocatedBytes
            if let date = usage.lastModified, date > (dataModified ?? .distantPast) { dataModified = date }
        }

        // Spotlight no siempre registra el último uso. Si la app ha escrito en sus datos más
        // recientemente, esa fecha es mejor indicio de que se usa.
        let lastUsed = [app.lastUsed, dataModified].compactMap { $0 }.max()
        let usedFromData = lastUsed != nil && lastUsed == dataModified && dataModified != app.lastUsed
        let isUnused = lastUsed.map { $0.isOlder(thanDays: unusedAppDays) } ?? true
        let total = app.appBytes.reclaimableBytes + dataBytes
        guard isUnused || total >= largeAppThreshold else { return nil }

        let isRunning = context.apps.isRunning(owner: app.identifier)
        let reinstall = app.isAppStore
            ? "Puedes reinstalarla gratis desde App Store › Comprado."
            : "Para reinstalarla necesitarás su instalador y, si es de pago, su licencia."
        let data = related.isEmpty ? "" : " También se moverán a la Papelera \(related.count) carpetas de datos (\(dataBytes.formatted(.byteCount(style: .file))))."

        let (risk, reason): (RiskLevel, String)
        if isRunning {
            (risk, reason) = (.high, "\(app.name) está abierta ahora mismo. Ciérrala antes de desinstalarla.\(data)")
        } else if let lastUsed, !lastUsed.isOlder(thanDays: unusedAppDays) {
            (risk, reason) = (.high, "La usaste \(lastUsed.relativeDescription): parece que la usas a menudo. \(reinstall)\(data)")
        } else if let lastUsed {
            (risk, reason) = (.moderate, "No la usas desde \(lastUsed.relativeDescription). \(reinstall)\(data)")
        } else {
            (risk, reason) = (.moderate, "No hay rastro de que la hayas abierto nunca: ni macOS lo registra ni ha guardado datos. \(reinstall)\(data)")
        }

        let lastUse = lastUsed.map { usedFromData ? "usada \($0.relativeDescription)" : "abierta \($0.relativeDescription)" } ?? "sin uso registrado"
        let detail = [
            app.version.map { "v\($0)" },
            lastUse,
            app.isAppStore ? "App Store" : nil,
            dataBytes > 0 ? "\(dataBytes.formatted(.byteCount(style: .file))) de datos" : nil,
        ].compactMap { $0 }.joined(separator: " · ")

        return ScanItem(
            id: app.path,
            displayName: app.name,
            location: context.displayPath((app.path as NSString).deletingLastPathComponent),
            category: isUnused ? .unusedApps : .largeApps,
            allocatedBytes: app.appBytes.allocatedBytes + dataAllocated,
            reclaimableBytes: total,
            lastModified: lastUsed,
            risk: risk,
            reason: reason,
            removal: .uninstallApp(relatedPaths: related),
            detail: detail
        )
    }

    /// Datos que una app deja en `~/Library` y que se desinstalan con ella.
    private static func relatedPaths(for app: AppCandidate, home: String) -> [String] {
        let library = home + "/Library"
        let id = app.identifier
        var candidates = [
            "\(library)/Application Support/\(id)",
            "\(library)/Caches/\(id)",
            "\(library)/Containers/\(id)",
            "\(library)/Preferences/\(id).plist",
            "\(library)/Saved Application State/\(id).savedState",
            "\(library)/HTTPStorages/\(id)",
            "\(library)/HTTPStorages/\(id).binarycookies",
            "\(library)/WebKit/\(id)",
            "\(library)/Logs/\(id)",
        ]
        // Carpetas con el nombre de la app, solo si el nombre es lo bastante específico.
        if app.name.count >= 4 {
            candidates += [
                "\(library)/Application Support/\(app.name)",
                "\(library)/Caches/\(app.name)",
                "\(library)/Logs/\(app.name)",
            ]
        }
        return candidates.filter { access($0, F_OK) == 0 }
    }

    private static func usage(ofPath path: String, context: MacScanContext) async throws -> TreeUsage {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return TreeUsage() }
        if isDirectory.boolValue {
            return try await context.measure(.directory(path))
        }
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        let bytes = Int64(values?.totalFileAllocatedSize ?? 0)
        return TreeUsage(entries: 1, allocatedBytes: bytes, reclaimableBytes: bytes)
    }

    /// Fecha de último uso según Spotlight (la misma que muestra el Finder).
    private static func lastUsedDate(ofItemAt path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: - Inicio y rendimiento

    static func startupItems(_ context: MacScanContext) async throws -> [ScanItem] {
        let running = await LaunchItemStatus.runningLabels()
        let roots: [(path: String, category: CleaningCategory, isDaemon: Bool)] = [
            (context.home + "/Library/LaunchAgents", .launchAgents, false),
            ("/Library/LaunchAgents", .systemLaunchItems, false),
            ("/Library/LaunchDaemons", .systemLaunchItems, true),
        ]

        var items: [ScanItem] = []
        for root in roots {
            for entry in context.entries(in: root.path, for: root.category) where entry.name.hasSuffix(".plist") {
                let path = root.path + "/" + entry.name
                guard let item = launchItem(
                    at: path, category: root.category, isDaemon: root.isDaemon,
                    running: running, context: context
                ) else { continue }
                items.append(item)
            }
        }
        return items
    }

    private static func launchItem(
        at path: String,
        category: CleaningCategory,
        isDaemon: Bool,
        running: [String: Int?],
        context: MacScanContext
    ) -> ScanItem? {
        guard let plist = NSDictionary(contentsOfFile: path),
              let label = plist["Label"] as? String,
              !label.hasPrefix("com.apple.") else { return nil }

        let arguments = plist["ProgramArguments"] as? [String]
        let executable = (plist["Program"] as? String) ?? arguments?.first
        let executableExists = executable.map { access($0, F_OK) == 0 } ?? true
        let owner = launchItemOwner(label: label, executable: executable, plist: plist, context: context)
        let hasOwnerApp = owner.isInstalledApp
        let behavior = launchBehavior(plist, isDaemon: isDaemon)
        let pid = running[label] ?? nil
        let isDisabled = plist["Disabled"] as? Bool == true

        let lower = (label + " " + (executable ?? "")).lowercased()
        let isUpdater = ["update", "keystone", "updater", "autoupdate", "sparkle"].contains(where: lower.contains)
        let keepsRunning = plist["KeepAlive"] != nil && (plist["KeepAlive"] as? Bool) != false

        let name = owner.name
        let (risk, reason): (RiskLevel, String)
        if !executableExists, let executable {
            (risk, reason) = (.safe, "El programa que lanzaba (\(context.displayPath(executable))) ya no existe: seguramente desinstalaste la app. Ahora solo genera errores en cada arranque.")
        } else if isDisabled {
            (risk, reason) = (.safe, "Está desactivado y no hace nada. El archivo sobra.")
        } else if !hasOwnerApp {
            (risk, reason) = (.moderate, "No hay ninguna app instalada de este fabricante: probablemente es un resto de una app que desinstalaste y sigue arrancando con el Mac.")
        } else if isUpdater {
            (risk, reason) = (.moderate, "Actualizador de \(name). Sin él, \(name) buscará actualizaciones al abrirla o tendrás que actualizarla a mano.")
        } else if keepsRunning {
            (risk, reason) = (.moderate, "\(name) lo mantiene siempre en ejecución y consume memoria y batería. Sin él dejarán de funcionar sus funciones en segundo plano (sincronización, icono de la barra de menús…).")
        } else {
            (risk, reason) = (.high, "Puede ser necesario para que \(name) funcione (controladores, VPN, copias de seguridad…). Quítalo solo si sabes qué hace.")
        }

        let status = pid.map { "en ejecución (PID \($0))" } ?? (running[label] != nil ? "cargado" : nil)
        return ScanItem(
            id: path,
            displayName: name,
            location: context.displayPath((path as NSString).deletingLastPathComponent),
            category: category,
            allocatedBytes: 0,
            reclaimableBytes: 0,
            lastModified: nil,
            risk: risk,
            reason: reason,
            removal: category == .launchAgents ? .launchAgent(label: label) : .systemLaunchItem(label: label),
            detail: [behavior, status, label].compactMap { $0 }.joined(separator: " · ")
        )
    }

    private struct LaunchItemOwner {
        let name: String
        let isInstalledApp: Bool
    }

    /// Nombre legible del dueño: la app que contiene el ejecutable, una app asociada o del
    /// mismo fabricante, o la etiqueta embellecida.
    private static func launchItemOwner(label: String, executable: String?, plist: NSDictionary, context: MacScanContext) -> LaunchItemOwner {
        if let executable, let range = executable.range(of: ".app/") {
            let appPath = String(executable[..<range.lowerBound]) + ".app"
            let name = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
            return LaunchItemOwner(name: name, isInstalledApp: access(appPath, F_OK) == 0)
        }
        let associated = plist["AssociatedBundleIdentifiers"] as? [String]
            ?? (plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        for identifier in associated + [label] {
            if let name = context.apps.displayName(forBundleIdentifier: identifier) {
                return LaunchItemOwner(name: name, isInstalledApp: true)
            }
        }
        // Ayudantes dentro de la carpeta de datos de una app (p. ej. Steam).
        if let executable, executable.hasPrefix(context.home + "/Library/Application Support/") {
            let folder = executable.dropFirst((context.home + "/Library/Application Support/").count).split(separator: "/").first.map(String.init)
            if let folder, let name = context.apps.appName(sharingVendorWith: label) ?? context.apps.displayName(forBundleIdentifier: folder) {
                return LaunchItemOwner(name: name, isInstalledApp: true)
            }
            if let folder { return LaunchItemOwner(name: "\(folder) · \(prettyLabel(label))", isInstalledApp: true) }
        }
        if let name = context.apps.appName(sharingVendorWith: label) {
            return LaunchItemOwner(name: "\(name) · \(prettyLabel(label))", isInstalledApp: true)
        }
        return LaunchItemOwner(name: prettyLabel(label), isInstalledApp: false)
    }

    /// "com.docker.socket" → "Docker socket"; "us.zoom.ZoomDaemon" → "Zoom ZoomDaemon".
    private static func prettyLabel(_ label: String) -> String {
        let parts = label.split(separator: ".").dropFirst()
        guard let vendor = parts.first else { return label }
        let rest = parts.dropFirst().joined(separator: " ")
        let name = vendor.prefix(1).uppercased() + vendor.dropFirst()
        return rest.isEmpty ? name : "\(name) \(rest)"
    }

    private static func launchBehavior(_ plist: NSDictionary, isDaemon: Bool) -> String {
        if plist["KeepAlive"] != nil && (plist["KeepAlive"] as? Bool) != false {
            return "Siempre activo"
        }
        if let interval = plist["StartInterval"] as? Int {
            return "Cada \(Duration.seconds(interval).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))"
        }
        if plist["StartCalendarInterval"] != nil {
            return "Programado"
        }
        if plist["RunAtLoad"] as? Bool == true {
            return isDaemon ? "Al arrancar el Mac" : "Al iniciar sesión"
        }
        if plist["WatchPaths"] != nil || plist["QueueDirectories"] != nil {
            return "Al cambiar archivos"
        }
        return "Bajo demanda"
    }
}

/// Estado de los servicios cargados en el dominio del usuario.
nonisolated enum LaunchItemStatus {
    static let launchctl = "/bin/launchctl"

    /// Etiqueta → PID (o `nil` si está cargado pero no en ejecución).
    static func runningLabels() async -> [String: Int?] {
        guard let output = try? await ProcessRunner.run(launchctl, arguments: ["list"]), output.succeeded else { return [:] }
        var result: [String: Int?] = [:]
        // Formato: "PID\tStatus\tLabel", con "-" si no está en ejecución.
        for line in output.output.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t")
            guard columns.count == 3 else { continue }
            result[String(columns[2])] = Int(columns[0])
        }
        return result
    }

    /// Detiene un servicio del dominio gráfico del usuario. Si no estaba cargado, no pasa nada.
    static func bootoutUserService(_ label: String) async {
        _ = try? await ProcessRunner.run(launchctl, arguments: ["bootout", "gui/\(getuid())/\(label)"])
    }
}
#endif
