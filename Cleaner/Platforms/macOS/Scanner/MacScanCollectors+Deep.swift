#if os(macOS)
import Foundation

/// Recolectores del análisis profundo: simuladores, datos de Xcode, adjuntos de Mail y
/// copias de seguridad de dispositivos.
nonisolated extension MacScanCollectors {

    // MARK: - Simuladores y runtimes

    static func simulators(_ context: MacScanContext) async throws -> [ScanItem] {
        let inventory = await SimulatorInventory.load()
        let devicesByDirectory = Dictionary(
            inventory.devices.compactMap { device in device.directory.map { ($0, device) } },
            uniquingKeysWith: { first, _ in first }
        )

        var items = try await context.measureEach(devicesByDirectory.keys.map { MeasureTarget.directory($0) }) { target, usage in
            guard let device = devicesByDirectory[target.path] else { return nil }
            let (risk, reason) = simulatorRisk(device)
            let runtime = SimulatorInventory.runtimeName(device.runtimeIdentifier)
            let lastUse = device.lastBootedAt.map { "usado \($0.relativeDescription)" } ?? "nunca arrancado"
            return context.item(
                target, usage: usage, displayName: device.name, category: .simulatorDevices,
                risk: risk, reason: reason, removal: .simulatorDevice(udid: device.udid),
                detail: "\(runtime) · \(lastUse)"
            )
        }

        for runtime in inventory.runtimes where runtime.deletable != false {
            let bytes = runtime.sizeBytes ?? 0
            guard bytes >= MacScanContext.minimumItemBytes else { continue }
            let users = inventory.devices(usingRuntime: runtime.runtimeIdentifier)
            let (risk, reason) = runtimeRisk(runtime, users: users, bytes: bytes)
            let usage = users.isEmpty ? "ningún simulador lo usa" : "\(users.count) simuladores"
            let path = runtime.path ?? "simruntime://\(runtime.identifier)"
            items.append(ScanItem(
                id: path,
                displayName: runtime.displayName,
                location: (path as NSString).deletingLastPathComponent,
                category: .simulatorRuntimes,
                allocatedBytes: bytes,
                reclaimableBytes: bytes,
                lastModified: runtime.lastUsedAt,
                risk: risk,
                reason: reason,
                removal: .simulatorRuntime(identifier: runtime.identifier),
                detail: usage
            ))
        }
        return items
    }

    private static func simulatorRisk(_ device: SimulatorInventory.Device) -> (RiskLevel, String) {
        if device.isAvailable == false {
            let cause = device.availabilityError ?? "su runtime ya no está instalado"
            return (.safe, "No puede arrancar (\(cause)). Ocupa espacio sin servir para nada.")
        }
        if device.isBooted {
            return (.high, "Está encendido ahora mismo. Se apagará y perderás las apps y los datos de prueba que tenga.")
        }
        guard let lastUse = device.lastBootedAt else {
            return (.safe, "Nunca se ha arrancado, así que no contiene apps ni datos tuyos. Xcode lo creó automáticamente.")
        }
        if lastUse.isOlder(thanDays: 90) {
            return (.safe, "No lo arrancas desde \(lastUse.relativeDescription). Perderás sus apps y datos de prueba, pero puedes crear otro igual en Xcode cuando lo necesites.")
        }
        return (.moderate, "Lo usaste \(lastUse.relativeDescription). Perderás las apps instaladas, cuentas de prueba y ajustes de este simulador.")
    }

    private static func runtimeRisk(
        _ runtime: SimulatorInventory.Runtime,
        users: [SimulatorInventory.Device],
        bytes: Int64
    ) -> (RiskLevel, String) {
        let size = bytes.formatted(.byteCount(style: .file))
        if !runtime.isReady {
            return (.safe, "Está en estado «\(runtime.state ?? "desconocido")» y no se puede usar.")
        }
        if users.isEmpty {
            return (.safe, "Ningún simulador lo usa. Si algún día lo necesitas, Xcode vuelve a descargarlo (\(size)).")
        }
        let names = users.prefix(3).map(\.name).joined(separator: ", ")
        let more = users.count > 3 ? " y \(users.count - 3) más" : ""
        return (.moderate, "Lo usan \(names)\(more). Dejarán de arrancar hasta que vuelvas a descargarlo (\(size)) en Xcode › Settings › Components.")
    }

    // MARK: - Otros datos de Xcode

    static func xcodeCaches(_ context: MacScanContext) async throws -> [ScanItem] {
        let xcode = context.home + "/Library/Developer/Xcode"
        let reasons: [String: String] = [
            xcode + "/DocumentationCache": "Documentación descargada. Xcode la vuelve a descargar cuando la abras.",
            xcode + "/DocumentationIndex": "Índice de búsqueda de la documentación. Se reconstruye automáticamente.",
            xcode + "/UserData/IB Support": "Datos temporales de Interface Builder. Se regeneran al abrir un storyboard.",
            xcode + "/Products": "Productos sueltos de «Build for Testing/Profiling». Se regeneran al compilar.",
            context.home + "/Library/Developer/DVTDownloads": "Descargas temporales de Xcode que ya se instalaron.",
        ]
        let names: [String: String] = [
            xcode + "/DocumentationCache": "Caché de documentación",
            xcode + "/DocumentationIndex": "Índice de documentación",
            xcode + "/UserData/IB Support": "Interface Builder",
            xcode + "/Products": "Productos de compilación",
            context.home + "/Library/Developer/DVTDownloads": "Descargas de Xcode",
        ]
        let targets = names.map { MeasureTarget.directory($0.key, name: $0.value) }
        return try await context.measureEach(targets) { target, usage in
            context.item(
                target, usage: usage, category: .xcodeCaches, risk: .safe,
                reason: reasons[target.path] ?? "Xcode lo regenera cuando hace falta.", removal: .delete
            )
        }
    }

    // MARK: - Adjuntos de Mail

    static func mailAttachments(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        // Cada adjunto abierto se guarda en una carpeta con nombre UUID.
        let targets = context.entries(in: root, for: .mailAttachments)
            .filter(\.isDirectory)
            .map { entry in
                let path = root + "/" + entry.name
                let file = (try? context.scanner.entries(in: path))?.first { !$0.name.hasPrefix(".") }
                return MeasureTarget.directory(path, name: file?.name ?? entry.name)
            }
        return try await context.measureEach(targets) { target, usage in
            let age = usage.lastModified.map { " Lo abriste \($0.relativeDescription)." } ?? ""
            return context.item(
                target, usage: usage, category: .mailAttachments, risk: .safe,
                reason: "Copia de un adjunto que abriste desde Mail. El original sigue en el mensaje.\(age)",
                removal: .delete
            )
        }
    }

    // MARK: - Copias de seguridad de iPhone y iPad

    static func deviceBackups(_ context: MacScanContext) async throws -> [ScanItem] {
        let root = context.home + "/Library/Application Support/MobileSync/Backup"
        let targets = context.entries(in: root, for: .deviceBackups)
            .filter(\.isDirectory)
            .map { MeasureTarget.directory(root + "/" + $0.name, name: $0.name) }

        return try await context.measureEach(targets) { target, usage in
            let info = backupInfo(at: target.path)
            let name = info.deviceName ?? "Dispositivo desconocido"
            let date = info.date ?? usage.lastModified
            let (risk, reason): (RiskLevel, String)
            if let date, date.isOlder(thanDays: 365) {
                (risk, reason) = (.moderate, "Copia de \(name) de \(date.relativeDescription). Probablemente esté desactualizada; comprueba que tienes una copia más reciente en iCloud o en otro Mac.")
            } else {
                (risk, reason) = (.high, "Copia de seguridad de \(name). Podría ser la única forma de restaurar ese dispositivo. Comprueba que tienes copia en iCloud antes de borrarla.")
            }
            return context.item(
                target, usage: usage, displayName: name, category: .deviceBackups,
                risk: risk, reason: reason, removal: .moveToTrash,
                detail: [info.product, date.map { "copia \($0.relativeDescription)" }].compactMap { $0 }.joined(separator: " · ")
            )
        }
    }

    private static func backupInfo(at path: String) -> (deviceName: String?, product: String?, date: Date?) {
        guard let data = FileManager.default.contents(atPath: path + "/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return (nil, nil, nil)
        }
        return (
            plist["Device Name"] as? String ?? plist["Display Name"] as? String,
            plist["Product Name"] as? String ?? plist["Product Type"] as? String,
            plist["Last Backup Date"] as? Date
        )
    }
}

// MARK: - Artefactos de proyectos

/// Carpetas regenerables dentro de proyectos, con la herramienta que las regenera.
nonisolated struct ProjectArtifact: Sendable {
    let label: String
    let regenerate: String

    /// Si `path` es un artefacto regenerable, lo identifica. Para nombres genéricos
    /// (`target`, `build`) exige el archivo de proyecto correspondiente al lado.
    static func classify(name: String, path: String) -> ProjectArtifact? {
        let parent = (path as NSString).deletingLastPathComponent
        func sibling(_ file: String) -> Bool { access(parent + "/" + file, F_OK) == 0 }
        func contains(_ file: String) -> Bool { access(path + "/" + file, F_OK) == 0 }

        switch name {
        case "node_modules":
            return ProjectArtifact(label: "node_modules", regenerate: "npm install")
        case "Pods" where sibling("Podfile"):
            return ProjectArtifact(label: "Pods", regenerate: "pod install")
        case ".build" where sibling("Package.swift"):
            return ProjectArtifact(label: "compilación de SwiftPM", regenerate: "swift build")
        case "target" where sibling("Cargo.toml"):
            return ProjectArtifact(label: "compilación de Rust", regenerate: "cargo build")
        case ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular":
            return sibling("package.json") ? ProjectArtifact(label: "caché de \(name)", regenerate: "npm run build") : nil
        case ".gradle", "build":
            let gradle = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"].contains(where: sibling)
            return gradle ? ProjectArtifact(label: "compilación de Gradle", regenerate: "./gradlew build") : nil
        case ".dart_tool" where sibling("pubspec.yaml"):
            return ProjectArtifact(label: "herramientas de Dart", regenerate: "flutter pub get")
        case ".venv", "venv", "env":
            return contains("pyvenv.cfg")
                ? ProjectArtifact(label: "entorno virtual de Python", regenerate: "pip install -r requirements.txt")
                : nil
        case "__pycache__":
            return ProjectArtifact(label: "bytecode de Python", regenerate: "se regenera al ejecutar")
        default:
            return nil
        }
    }
}
#endif
