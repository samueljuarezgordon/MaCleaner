#if os(macOS)
import Foundation

/// Inventario de simuladores y runtimes de Xcode leído con `simctl … -j`.
///
/// Todos los campos del JSON son opcionales: el formato cambia entre versiones de Xcode y
/// un campo que falta no debe impedir listar el resto.
nonisolated struct SimulatorInventory: Sendable {
    struct Device: Sendable, Decodable {
        let udid: String
        let name: String
        let state: String?
        let isAvailable: Bool?
        let availabilityError: String?
        let dataPath: String?
        private let lastBootedAtRaw: LenientDate?
        let deviceTypeIdentifier: String?
        /// Se rellena al decodificar: la clave del diccionario en el que aparece.
        var runtimeIdentifier = ""

        private enum CodingKeys: String, CodingKey {
            case udid, name, state, isAvailable, availabilityError, dataPath, deviceTypeIdentifier
            case lastBootedAtRaw = "lastBootedAt"
        }

        var lastBootedAt: Date? { lastBootedAtRaw?.date }

        var isBooted: Bool { state == "Booted" }

        /// `~/Library/Developer/CoreSimulator/Devices/<UDID>`
        var directory: String? {
            dataPath.map { ($0 as NSString).deletingLastPathComponent }
        }
    }

    struct Runtime: Sendable, Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let platformIdentifier: String?
        let runtimeIdentifier: String?
        let state: String?
        let deletable: Bool?
        let sizeBytes: Int64?
        private let lastUsedAtRaw: LenientDate?
        let path: String?

        private enum CodingKeys: String, CodingKey {
            case identifier, version, build, platformIdentifier, runtimeIdentifier, state, deletable, sizeBytes, path
            case lastUsedAtRaw = "lastUsedAt"
        }

        var lastUsedAt: Date? { lastUsedAtRaw?.date }

        /// "iOS 18.2 (22C150)"
        var displayName: String {
            let platform = Self.platformName(platformIdentifier ?? runtimeIdentifier ?? "")
            let base = [platform, version].compactMap { $0 }.joined(separator: " ")
            return build.map { "\(base) (\($0))" } ?? base
        }

        var isReady: Bool { state == nil || state == "Ready" }

        static func platformName(_ identifier: String) -> String? {
            let lower = identifier.lowercased()
            if lower.contains("iphone") || lower.contains("ios") { return "iOS" }
            if lower.contains("watch") { return "watchOS" }
            if lower.contains("appletv") || lower.contains("tvos") { return "tvOS" }
            if lower.contains("xr") || lower.contains("vision") { return "visionOS" }
            return nil
        }
    }

    let devices: [Device]
    let runtimes: [Runtime]

    static let empty = SimulatorInventory(devices: [], runtimes: [])

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" → "iOS 18.2"
    static func runtimeName(_ identifier: String) -> String {
        let suffix = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = suffix.split(separator: "-")
        guard let platform = parts.first else { return suffix }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }

    func devices(usingRuntime identifier: String?) -> [Device] {
        guard let identifier else { return [] }
        return devices.filter { $0.runtimeIdentifier == identifier }
    }

    // MARK: - Lectura

    private static let xcrun = "/usr/bin/xcrun"

    /// Lee simuladores y runtimes. Si Xcode no está instalado, devuelve un inventario vacío.
    static func load() async -> SimulatorInventory {
        async let devices = loadDevices()
        async let runtimes = loadRuntimes()
        return SimulatorInventory(devices: await devices, runtimes: await runtimes)
    }

    private static func loadDevices() async -> [Device] {
        struct Listing: Decodable { let devices: [String: [Device]] }
        guard let listing: Listing = await decode(["simctl", "list", "devices", "-j"]) else { return [] }
        return listing.devices.flatMap { runtime, devices in
            devices.map { device in
                var device = device
                device.runtimeIdentifier = runtime
                return device
            }
        }
    }

    private static func loadRuntimes() async -> [Runtime] {
        // `simctl runtime list -j` devuelve un diccionario indexado por identificador.
        guard let listing: [String: Runtime] = await decode(["simctl", "runtime", "list", "-j"]) else { return [] }
        return Array(listing.values)
    }

    private static func decode<T: Decodable>(_ arguments: [String]) async -> T? {
        guard FileManager.default.isExecutableFile(atPath: xcrun),
              let output = try? await ProcessRunner.run(xcrun, arguments: arguments),
              output.succeeded else { return nil }
        // La salida puede llevar avisos antes del JSON.
        guard let start = output.output.firstIndex(of: "{") else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(output.output[start...].utf8))
    }
}

/// Fecha ISO 8601 que nunca hace fallar la decodificación: si no se entiende, queda en `nil`.
private nonisolated struct LenientDate: Decodable, Sendable {
    let date: Date?

    init(from decoder: any Decoder) throws {
        guard let string = try? decoder.singleValueContainer().decode(String.self) else {
            date = nil
            return
        }
        date = (try? Date(string, strategy: .iso8601))
            ?? (try? Date(string, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
    }
}
#endif
