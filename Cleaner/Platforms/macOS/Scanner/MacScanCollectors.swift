#if os(macOS)
import AppKit
import Foundation

/// Recolectores de la limpieza profunda de macOS. Cada uno busca una o varias categorías y
/// asigna a cada elemento su riesgo y una explicación.
nonisolated enum MacScanCollectors {

    // MARK: - Basura del sistema

    static func userCaches(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Library/Caches"
        let targets = context.entries(in: root, for: .userCaches)
            .filter { $0.isDirectory && !excludedCacheNames.contains($0.name) }
            .map { MeasureTarget.directory(root + "/" + $0.name, name: $0.name) }

        var items = try await context.measureEach(targets) { target, usage in
            let (risk, reason) = cacheRisk(owner: target.name, context: context)
            return context.item(
                target, usage: usage, displayName: context.friendlyName(for: target.name),
                category: .userCaches, risk: risk, reason: reason, removal: .delete
            )
        }

        // Cachés dentro de los contenedores de apps con sandbox.
        let containers = context.home + "/Library/Containers"
        let containerTargets = context.entries(in: containers, for: .userCaches)
            .filter { $0.isDirectory && !$0.name.hasPrefix(".") }
            .map { MeasureTarget.directory(containers + "/" + $0.name + "/Data/Library/Caches", name: $0.name) }

        items += try await context.measureEach(containerTargets) { target, usage in
            let (risk, reason) = cacheRisk(owner: target.name, context: context)
            return context.item(
                target, usage: usage, displayName: context.friendlyName(for: target.name) + " (sandbox)",
                category: .userCaches, risk: risk, reason: reason, removal: .delete
            )
        }
        return items
    }

    /// Cachés de Chromium/Electron dentro de `~/Library/Application Support/<App>/…`.
    static func appCaches(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Library/Application Support"
        let appFolders = context.entries(in: root, for: .appCaches)
            .filter { $0.isDirectory && !$0.name.hasPrefix(".") && !$0.name.hasPrefix("com.apple.") }

        // Paso 1: localizar carpetas de caché (sin recorrerlas) hasta 4 niveles de profundidad.
        let locator = TraversalOptions(maxDepth: 4) { name, _ in
            appCacheDirectoryNames.contains(name) ? .collect : .descend
        }
        var found: [(owner: String, path: String)] = []
        try await withThrowingTaskGroup(of: (String, [String]).self) { group in
            for folder in appFolders {
                group.addTask {
                    let usage = try await context.scanner.measureTree(
                        at: root + "/" + folder.name, metrics: context.metrics, options: locator
                    )
                    return (folder.name, usage.collectedDirectories)
                }
            }
            for try await (owner, paths) in group {
                found += paths.map { (owner, $0) }
            }
        }

        // Paso 2: medir cada caché encontrada.
        let owners = Dictionary(found.map { ($0.path, $0.owner) }, uniquingKeysWith: { first, _ in first })
        let targets = found.map { MeasureTarget.directory($0.path) }
        return try await context.measureEach(targets) { target, usage in
            let owner = owners[target.path] ?? target.name
            let ownerRoot = root + "/" + owner + "/"
            let relative = target.path.hasPrefix(ownerRoot) ? String(target.path.dropFirst(ownerRoot.count)) : target.name
            let appName = context.friendlyName(for: owner)

            let (risk, reason): (RiskLevel, String) = context.apps.isRunning(owner: owner)
                ? (.moderate, "\(appName) está abierta. Ciérrala antes de limpiar; después es seguro.")
                : (.safe, "Caché de \(appName). Se regenera automáticamente al abrir la app.")
            return context.item(
                target, usage: usage, displayName: "\(appName) · \(relative)",
                category: .appCaches, risk: risk, reason: reason, removal: .delete
            )
        }
    }

    static func systemCaches(_ context: MacScanContext) async throws -> [ScanItem] {
        try await children(
            of: "/Library/Caches", category: .systemCaches, context: context,
            risk: .safe, reason: "Caché del sistema. macOS la regenera cuando la necesita.",
            removal: .privileged
        )
    }

    static func userLogs(_ context: MacScanContext) async throws -> [ScanItem] {
        try await children(
            of: context.home + "/Library/Logs", category: .userLogs, context: context,
            risk: .safe, reason: "Registros de actividad y fallos. Solo sirven para diagnosticar problemas antiguos.",
            removal: .delete
        )
    }

    static func systemLogs(_ context: MacScanContext) async throws -> [ScanItem] {
        var items: [ScanItem] = []
        for root in ["/Library/Logs", "/private/var/log"] {
            items += try await children(
                of: root, category: .systemLogs, context: context,
                risk: .safe, reason: "Registros del sistema. macOS crea registros nuevos automáticamente.",
                removal: .privileged
            )
        }
        return items
    }

    // MARK: - Desarrollo

    static func derivedData(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Library/Developer/Xcode/DerivedData"
        let targets = context.entries(in: root, for: .xcodeDerivedData)
            .filter(\.isDirectory)
            .map { MeasureTarget.directory(root + "/" + $0.name, name: $0.name) }

        return try await context.measureEach(targets) { target, usage in
            // "MiApp-abcdefghijklmnopqrstuvwxyzab" → "MiApp"
            let name = target.name.range(of: #"-[a-z]{28}$"#, options: .regularExpression)
                .map { String(target.name[..<$0.lowerBound]) } ?? target.name
            return context.item(
                target, usage: usage, displayName: name, category: .xcodeDerivedData, risk: .safe,
                reason: "Productos de compilación de Xcode. La próxima compilación de \(name) tardará algo más.",
                removal: .delete
            )
        }
    }

    static func deviceSupport(_ context: MacScanContext) async throws -> [ScanItem] {
        let base = context.home + "/Library/Developer/Xcode"
        var targets: [MeasureTarget] = []
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            let root = base + "/\(platform) DeviceSupport"
            targets += context.entries(in: root, for: .xcodeDeviceSupport)
                .filter(\.isDirectory)
                .map { MeasureTarget.directory(root + "/" + $0.name, name: "\(platform) · \($0.name)") }
        }

        return try await context.measureEach(targets) { target, usage in
            let (risk, reason): (RiskLevel, String)
            if let date = usage.lastModified, date.isOlder(thanDays: 180) {
                (risk, reason) = (.safe, "Versión antigua: no la usas desde \(date.relativeDescription). Si vuelves a conectar ese dispositivo, Xcode copiará los símbolos de nuevo.")
            } else {
                (risk, reason) = (.moderate, "Versión reciente. Si la borras, Xcode tardará unos minutos en volver a copiar los símbolos la próxima vez que conectes el dispositivo.")
            }
            return context.item(
                target, usage: usage, category: .xcodeDeviceSupport, risk: risk, reason: reason, removal: .delete
            )
        }
    }

    static func xcodeArchives(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Library/Developer/Xcode/Archives"
        var targets: [MeasureTarget] = []
        for day in context.entries(in: root, for: .xcodeArchives) where day.isDirectory {
            let dayPath = root + "/" + day.name
            targets += context.entries(in: dayPath, for: .xcodeArchives)
                .filter { $0.name.hasSuffix(".xcarchive") }
                .map { MeasureTarget.directory(dayPath + "/" + $0.name, name: ($0.name as NSString).deletingPathExtension) }
        }
        return try await context.measureEach(targets) { target, usage in
            context.item(
                target, usage: usage, category: .xcodeArchives, risk: .high,
                reason: "Contiene los dSYM necesarios para interpretar informes de fallos de esta versión. Bórralo solo si ya no das soporte a esa versión.",
                removal: .moveToTrash
            )
        }
    }

    static func simulatorCaches(_ context: MacScanContext) async throws -> [ScanItem] {
        let developer = context.home + "/Library/Developer"
        let targets: [MeasureTarget] = [
            .directory(developer + "/CoreSimulator/Caches", name: "Cachés de CoreSimulator"),
            .directory(developer + "/Xcode/UserData/Previews", name: "Vistas previas de SwiftUI"),
            .directory(developer + "/XCPGDevices", name: "Simuladores de Playgrounds"),
            .directory(developer + "/Xcode/iOS Device Logs", name: "Registros de dispositivos"),
        ]
        return try await context.measureEach(targets) { target, usage in
            context.item(
                target, usage: usage, category: .simulatorCaches, risk: .safe,
                reason: "Xcode lo regenera automáticamente cuando hace falta.",
                removal: .delete
            )
        }
    }

    static func packageCaches(_ context: MacScanContext) async throws -> [ScanItem] {
        let home = context.home
        var targets: [MeasureTarget] = [
            .directory(home + "/.npm/_cacache", name: "npm"),
            .directory(home + "/Library/pnpm/store", name: "pnpm"),
            .directory(home + "/.yarn/berry/cache", name: "Yarn"),
            .directory(home + "/.bun/install/cache", name: "Bun"),
            .directory(home + "/.gradle/caches", name: "Gradle"),
            .directory(home + "/.gradle/wrapper/dists", name: "Distribuciones de Gradle"),
            .directory(home + "/.m2/repository", name: "Maven"),
            .directory(home + "/.cargo/registry/cache", name: "Cargo"),
            .directory(home + "/go/pkg/mod/cache", name: "Módulos de Go"),
            .directory(home + "/.cocoapods/repos", name: "Especificaciones de CocoaPods"),
            .directory(home + "/.android/cache", name: "Android SDK"),
            .directory(home + "/.nuget/packages", name: "NuGet"),
            .directory(home + "/.pub-cache", name: "Dart y Flutter (pub)"),
            .directory(home + "/.ivy2/cache", name: "Ivy"),
            .directory(home + "/.cargo/git/checkouts", name: "Cargo (repositorios git)"),
            .directory(home + "/.conda/pkgs", name: "Conda"),
            .directory(home + "/miniconda3/pkgs", name: "Miniconda"),
            .directory(home + "/anaconda3/pkgs", name: "Anaconda"),
        ]
        // ~/.cache: un elemento por herramienta (pip, uv, huggingface…).
        let genericCache = home + "/.cache"
        targets += context.entries(in: genericCache, for: .packageCaches)
            .filter(\.isDirectory)
            .map { MeasureTarget.directory(genericCache + "/" + $0.name, name: "~/.cache · \($0.name)") }

        return try await context.measureEach(targets) { target, usage in
            let reason = target.path.contains("huggingface")
                ? "Modelos de IA descargados. Se volverán a descargar si los usas, lo que puede tardar mucho."
                : "Paquetes descargados. Se volverán a descargar la próxima vez que un proyecto los necesite."
            return context.item(
                target, usage: usage, category: .packageCaches, risk: .moderate, reason: reason, removal: .delete
            )
        }
    }

    // MARK: - Descargas

    static func downloads(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Downloads"
        let entries = context.entries(in: root, for: .installers)
        let folderNames = Set(entries.filter(\.isDirectory).map { $0.name.lowercased() })

        var targets: [MeasureTarget] = []
        for entry in entries where !entry.name.hasPrefix(".") {
            let path = root + "/" + entry.name
            let ext = (entry.name as NSString).pathExtension.lowercased()
            if entry.isDirectory {
                if ext == "app" { targets.append(.directory(path, name: entry.name)) }
            } else if installerExtensions.contains(ext) || archiveExtensions.contains(ext) {
                targets.append(MeasureTarget(path: path, name: entry.name, file: entry))
            }
        }

        // Actualizaciones de iOS/iPadOS que descargó el Finder.
        for folder in ["iPhone Software Updates", "iPad Software Updates"] {
            let updates = context.home + "/Library/iTunes/" + folder
            for entry in context.entries(in: updates, for: .installers) where entry.name.lowercased().hasSuffix(".ipsw") {
                targets.append(MeasureTarget(path: updates + "/" + entry.name, name: entry.name, file: entry))
            }
        }

        // Instaladores de macOS que quedan en /Applications.
        for entry in context.entries(in: "/Applications", for: .installers)
        where entry.name.hasPrefix("Install macOS") && entry.name.hasSuffix(".app") {
            targets.append(.directory("/Applications/" + entry.name, name: entry.name))
        }

        return try await context.measureEach(targets) { target, usage in
            let ext = (target.name as NSString).pathExtension.lowercased()
            let age = usage.lastModified.map { " Descargado \($0.relativeDescription)." } ?? ""

            if archiveExtensions.contains(ext) {
                let base = archiveBaseName(target.name).lowercased()
                let (risk, reason): (RiskLevel, String) = folderNames.contains(base)
                    ? (.moderate, "Ya existe la carpeta descomprimida «\(archiveBaseName(target.name))» al lado. Comprueba que está completa antes de borrar el comprimido.\(age)")
                    : (.high, "Archivo comprimido: puede ser la única copia de su contenido.\(age)")
                return context.item(
                    target, usage: usage, category: .compressedArchives, risk: risk, reason: reason, removal: .moveToTrash
                )
            }

            let reason: String
            if target.path.contains("Software Updates/") {
                return context.item(
                    target, usage: usage, category: .installers, risk: .safe,
                    reason: "Actualización de iOS o iPadOS que descargó el Finder. Si la necesitas, se vuelve a descargar sola.",
                    removal: .delete
                )
            }
            if target.path.hasPrefix("/Applications/") {
                reason = "Instalador de macOS. Puedes volver a descargarlo desde el App Store."
            } else if ext == "app" {
                reason = "App que nunca se movió a Aplicaciones. Si la usas, muévela en lugar de borrarla.\(age)"
            } else {
                reason = "Instalador. Si ya instalaste la app, no lo necesitas; puedes volver a descargarlo.\(age)"
            }
            return context.item(
                target, usage: usage, category: .installers, risk: .moderate, reason: reason, removal: .moveToTrash
            )
        }
    }

    // MARK: - Restos de apps

    static func appLeftovers(_ context: MacScanContext) async throws -> [ScanItem] {
        let library = context.home + "/Library"
        let locations = ["Application Support", "Containers", "Saved Application State", "HTTPStorages", "WebKit"]

        var candidates: [(target: MeasureTarget, identifier: String, ownership: InstalledAppIndex.Ownership)] = []
        for location in locations {
            let root = library + "/" + location
            for entry in context.entries(in: root, for: .appLeftovers) {
                let identifier = entry.name.hasSuffix(".savedState") ? String(entry.name.dropLast(11)) : entry.name
                guard InstalledAppIndex.looksLikeBundleIdentifier(identifier),
                      !identifier.hasPrefix("com.apple."), !identifier.hasPrefix("group.") else { continue }

                let ownership = context.apps.ownership(ofBundleLikeName: identifier)
                guard ownership != .installed else { continue }
                let target = entry.isDirectory
                    ? MeasureTarget.directory(root + "/" + entry.name, name: entry.name)
                    : MeasureTarget(path: root + "/" + entry.name, name: entry.name, file: entry)
                candidates.append((target, identifier, ownership))
            }
        }

        // Segunda comprobación con LaunchServices: encuentra apps instaladas fuera de las
        // carpetas habituales (juegos de Steam, apps en Descargas…).
        let unresolved = candidates.filter { $0.ownership != .installed }.map(\.identifier)
        let registered = await InstalledAppIndex.registeredIdentifiers(among: unresolved)
        candidates.removeAll { registered.contains($0.identifier.lowercased()) }

        let info = Dictionary(candidates.map { ($0.target.path, ($0.identifier, $0.ownership)) }, uniquingKeysWith: { first, _ in first })
        return try await context.measureEach(candidates.map(\.target)) { target, usage in
            guard let (identifier, ownership) = info[target.path] else { return nil }
            let (risk, reason): (RiskLevel, String)
            switch ownership {
            case .residualCopy(let owner):
                let app = context.apps.displayName(forBundleIdentifier: owner) ?? owner
                (risk, reason) = (.moderate, "Copia residual que dejó \(app) al restablecerse o actualizarse. La app ya no la usa; se moverá a la Papelera por si acaso.")
            case .sameVendor(let vendor):
                (risk, reason) = (.high, "No hay ninguna app con el identificador \(identifier), pero sí otras de \(vendor). Podría ser de una de ellas.")
            case .orphan, .installed:
                (risk, reason) = (.moderate, "No hay ninguna app instalada con el identificador \(identifier). Si la reinstalas, perderás su configuración.")
            }
            return context.item(
                target, usage: usage, category: .appLeftovers, risk: risk, reason: reason, removal: .moveToTrash
            )
        }
    }

    // MARK: - Carpeta de inicio: archivos grandes y node_modules

    static let largeFileThreshold: Int64 = 500 * 1024 * 1024

    static func homeArtifacts(_ context: MacScanContext) async throws -> [ScanItem] {
        let home = context.home
        let options = TraversalOptions(largeFileThreshold: largeFileThreshold) { name, path in
            if ProjectArtifact.classify(name: name, path: path) != nil { return .collect }
            // Carpetas ocultas (.git, .venv…) y paquetes que no se pueden vaciar a medias.
            if name.hasPrefix(".") { return .skip }
            if packageExtensions.contains((name as NSString).pathExtension.lowercased()) { return .skip }
            return .descend
        }

        var largeFiles: [FoundFile] = []
        var dependencies: [String] = []
        let roots = context.entries(in: home, for: .largeFiles)
        for entry in roots where !entry.isDirectory && entry.allocatedBytes >= largeFileThreshold {
            largeFiles.append(FoundFile(
                path: home + "/" + entry.name, name: entry.name, allocatedBytes: entry.allocatedBytes,
                reclaimableBytes: entry.reclaimableBytes, modificationDate: entry.modificationDate
            ))
        }

        let folders = roots.filter { $0.isDirectory && !$0.name.hasPrefix(".") && !homeExcludedFolders.contains($0.name) }
        try await withThrowingTaskGroup(of: TreeUsage.self) { group in
            for folder in folders {
                group.addTask {
                    try await context.scanner.measureTree(at: home + "/" + folder.name, metrics: context.metrics, options: options)
                }
            }
            for try await usage in group {
                largeFiles += usage.largeFiles
                dependencies += usage.collectedDirectories
                context.reportMetrics()
            }
        }

        var items: [ScanItem] = largeFiles.map { file in
            let target = MeasureTarget(path: file.path, name: file.name, file: nil)
            let usage = TreeUsage(
                entries: 1, allocatedBytes: file.allocatedBytes, reclaimableBytes: file.reclaimableBytes,
                lastModified: file.modificationDate
            )
            return context.item(
                target, usage: usage, category: .largeFiles, risk: .high,
                reason: "Archivo personal. Lo modificaste por última vez \(file.modificationDate.relativeDescription). Decide tú si lo necesitas; irá a la Papelera.",
                removal: .moveToTrash
            )
        }

        items += try await context.measureEach(dependencies.map { MeasureTarget.directory($0) }) { target, usage in
            guard let artifact = ProjectArtifact.classify(name: target.name, path: target.path) else { return nil }
            let project = ((target.path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            let (risk, reason): (RiskLevel, String)
            if let date = usage.lastModified, date.isOlder(thanDays: 90) {
                (risk, reason) = (.safe, "El proyecto «\(project)» no se toca desde \(date.relativeDescription). Si vuelves a él, se regenera con «\(artifact.regenerate)».")
            } else {
                (risk, reason) = (.moderate, "Proyecto activo: tendrás que ejecutar «\(artifact.regenerate)» para volver a trabajar en él.")
            }
            return context.item(
                target, usage: usage, displayName: project,
                category: .projectDependencies, risk: risk, reason: reason, removal: .delete,
                detail: artifact.label
            )
        }
        return items
    }

    // MARK: - Papelera

    static func trash(_ context: MacScanContext) async throws -> [ScanItem] {
        try await children(
            of: context.home + "/.Trash", category: .trash, context: context,
            risk: .safe, reason: "Ya está en la Papelera. Al vaciarla no se podrá recuperar.",
            removal: .delete
        )
    }

    // MARK: - Utilidades

    /// Un elemento por cada hijo inmediato de `root`.
    private static func children(
        of root: String,
        category: CleaningCategory,
        context: MacScanContext,
        risk: RiskLevel,
        reason: String,
        removal: RemovalMethod
    ) async throws -> [ScanItem] {
        let targets = context.entries(in: root, for: category)
            .filter { !$0.name.hasPrefix(".DS_Store") }
            .map { entry in
                entry.isDirectory
                    ? MeasureTarget.directory(root + "/" + entry.name, name: entry.name)
                    : MeasureTarget(path: root + "/" + entry.name, name: entry.name, file: entry)
            }
        return try await context.measureEach(targets) { target, usage in
            context.item(
                target, usage: usage, displayName: context.friendlyName(for: target.name),
                category: category, risk: risk, reason: reason, removal: removal
            )
        }
    }

    private static func cacheRisk(owner: String, context: MacScanContext) -> (RiskLevel, String) {
        let lower = owner.lowercased()
        if let tool = packageManagerCaches.first(where: { lower.contains($0.key) })?.value {
            return (.moderate, "Paquetes descargados por \(tool). Se volverán a descargar cuando los necesites.")
        }
        if syncCaches.contains(where: lower.contains) {
            return (.moderate, "Datos de sincronización de iCloud. Se volverán a descargar, lo que puede tardar.")
        }
        if context.apps.isRunning(owner: owner) {
            return (.moderate, "\(context.friendlyName(for: owner)) está abierta. Ciérrala antes de limpiar; después es seguro.")
        }
        return (.safe, "Caché temporal. La app la regenerará cuando la necesite.")
    }

    private static func archiveBaseName(_ name: String) -> String {
        var base = name
        while archiveExtensions.contains((base as NSString).pathExtension.lowercased()) {
            base = (base as NSString).deletingPathExtension
        }
        return base
    }

    // MARK: - Tablas de reglas

    private static let excludedCacheNames: Set<String> = [HelperConstants.appBundleIdentifier]

    private static let appCacheDirectoryNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "CachedData", "DawnCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "GrShaderCache", "GraphiteDawnCache", "ShaderCache", "CacheStorage",
        "CachedExtensionVSIXs", "ScriptCache", "component_crx_cache", "htmlcache", "logs", "Crashpad",
    ]

    private static let packageManagerCaches: [String: String] = [
        "homebrew": "Homebrew", "cocoapods": "CocoaPods", "pip": "pip", "yarn": "Yarn",
        "org.swift.swiftpm": "Swift Package Manager", "ms-playwright": "Playwright",
        "node-gyp": "node-gyp", "carthage": "Carthage", "go-build": "Go", "jetbrains": "JetBrains",
    ]

    private static let syncCaches = [
        "cloudkit", "com.apple.bird", "com.apple.cloudd", "com.apple.nsurlsessiond",
        "familycircle", "com.apple.homed",
    ]

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "ipsw", "iso"]

    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "tbz", "zst", "cpgz",
    ]

    /// Paquetes que se tratan como una unidad y nunca se vacían por dentro.
    private static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary", "imovielibrary",
        "fcpbundle", "lrlibrary", "aplibrary", "logicx", "band", "vmwarevm", "pvm", "utm",
    ]

    /// Carpetas de inicio que se analizan en otras categorías.
    private static let homeExcludedFolders: Set<String> = ["Library", "Applications"]
}

extension InstalledAppIndex {
    /// Identificadores (en minúsculas) que LaunchServices conoce como apps instaladas.
    static func registeredIdentifiers(among identifiers: [String]) async -> Set<String> {
        guard !identifiers.isEmpty else { return [] }
        return await MainActor.run {
            Set(identifiers.filter {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }.map { $0.lowercased() })
        }
    }
}
#endif
