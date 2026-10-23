#if os(macOS)
import Foundation

/// Limpieza de simuladores de Xcode.
///
/// - Important: Se ejecuta en la app (contexto del usuario), NO en el demonio. `simctl`
///   trabaja sobre `~/Library/Developer/CoreSimulator` del usuario que lo invoca. Como root
///   operaría sobre los simuladores de root y no liberaría nada.
nonisolated enum SimulatorCleaner {
    private static let xcrun = "/usr/bin/xcrun"

    /// Borra el contenido y los ajustes de TODOS los simuladores. `erase` exige que estén
    /// apagados, así que primero se apagan.
    static func eraseAllSimulators() async throws -> ProcessOutput {
        _ = try await ProcessRunner.run(xcrun, arguments: ["simctl", "shutdown", "all"])
        return try await ProcessRunner.run(xcrun, arguments: ["simctl", "erase", "all"])
    }

    /// Elimina los runtimes inutilizables y los dispositivos que ya no tienen runtime.
    ///
    /// `simctl runtime delete` no admite el alias `unavailable`; el equivalente es
    /// `--unusable`. Los dispositivos huérfanos se eliminan con `simctl delete unavailable`.
    static func deleteUnusableRuntimes() async throws -> [ProcessOutput] {
        let runtimes = try await ProcessRunner.run(xcrun, arguments: ["simctl", "runtime", "delete", "--unusable"])
        let devices = try await ProcessRunner.run(xcrun, arguments: ["simctl", "delete", "unavailable"])
        return [runtimes, devices]
    }

    /// Apaga (si hace falta) y elimina un simulador concreto.
    static func deleteDevice(udid: String) async throws -> ProcessOutput {
        _ = try? await ProcessRunner.run(xcrun, arguments: ["simctl", "shutdown", udid])
        return try await ProcessRunner.run(xcrun, arguments: ["simctl", "delete", udid])
    }

    /// Elimina un runtime de simulador por su identificador.
    static func deleteRuntime(identifier: String) async throws -> ProcessOutput {
        try await ProcessRunner.run(xcrun, arguments: ["simctl", "runtime", "delete", identifier])
    }
}
#endif

#if os(macOS)
/// Reparaciones del sistema que se ejecutan en el contexto del usuario.
nonisolated enum SystemRepair {
    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    /// Vacía y reconstruye la base de datos de LaunchServices del usuario.
    static func rebuildLaunchServices() async throws -> ProcessOutput {
        try await ProcessRunner.run(lsregister, arguments: [
            "-kill", "-r", "-domain", "local", "-domain", "system", "-domain", "user",
        ])
    }

    /// Restablece los generadores y la caché de miniaturas de Quick Look.
    static func resetQuickLook() async throws -> [ProcessOutput] {
        let generators = try await ProcessRunner.run("/usr/bin/qlmanage", arguments: ["-r"])
        let cache = try await ProcessRunner.run("/usr/bin/qlmanage", arguments: ["-r", "cache"])
        return [generators, cache]
    }
}
#endif
