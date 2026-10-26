#if os(macOS)
import Foundation
import Security

/// Comprueba el asistente privilegiado de principio a fin (firma, bundle, registro, launchd
/// y respuesta XPC) para saber en qué punto falla sin usar Terminal.
enum HelperDiagnostics {
    struct Check: Identifiable, Sendable {
        enum Status: Sendable {
            case ok, warning, failure, info
        }

        let id = UUID()
        let title: String
        let detail: String
        let status: Status
    }

    /// Lo que launchd sabe del demonio (`launchctl print system/<label>`).
    struct LaunchdState: Sendable {
        var isLoaded = false
        var state: String?
        var runs: Int?
        var lastExitCode: String?
        var pid: Int?
    }

    static func run() async -> [Check] {
        var checks: [Check] = []
        let bundle = Bundle.main.bundleURL

        // 1. Firma de la app.
        let appTeam = CodeSigningValidator.currentTeamIdentifier()
        checks.append(appTeam.map {
            Check(title: "Firma de la app", detail: "Equipo \($0)", status: .ok)
        } ?? Check(
            title: "Firma de la app",
            detail: "Sin Team ID (firma ad hoc). El asistente rechaza todas las conexiones por seguridad.",
            status: .failure
        ))

        // 2. El asistente va dentro de la app y está firmado por el mismo equipo.
        let helperPath = bundle.appending(path: "Contents/MacOS/CleanerHelper").path
        let plistPath = bundle.appending(path: "Contents/Library/LaunchDaemons/\(HelperConstants.daemonPlistName)").path
        if !FileManager.default.fileExists(atPath: helperPath) || !FileManager.default.fileExists(atPath: plistPath) {
            checks.append(Check(
                title: "Asistente dentro de la app",
                detail: "Falta \(FileManager.default.fileExists(atPath: helperPath) ? plistPath : helperPath).",
                status: .failure
            ))
        } else {
            let helperTeam = teamIdentifier(ofFileAt: helperPath)
            let matches = helperTeam != nil && helperTeam == appTeam
            checks.append(Check(
                title: "Asistente dentro de la app",
                detail: matches
                    ? String(localized: "Presente y firmado por el mismo equipo.")
                    : String(localized: "Firmado por otro equipo (\(helperTeam ?? "ninguno")): la app y el asistente no se aceptarán."),
                status: matches ? .ok : .failure
            ))
        }

        // 3. Ubicación: con varias copias, macOS puede lanzar el asistente de otra.
        let inApplications = bundle.path.hasPrefix("/Applications/")
        checks.append(Check(
            title: "Ubicación de la app",
            detail: inApplications
                ? bundle.path
                : String(localized: "\(bundle.path). Si hay otras copias de MaCleaner, borra las que no uses y pulsa «Reinstalar» en esta."),
            status: inApplications ? .ok : .warning
        ))

        // 4. Registro en el sistema.
        let state = HelperInstaller.state
        let registration = switch state {
        case .enabled: String(localized: "Activo en Ítems de inicio y extensiones.")
        case .requiresApproval: String(localized: "Pendiente de aprobar en Ajustes del Sistema › General › Ítems de inicio y extensiones.")
        case .notRegistered: String(localized: "No registrado. Pulsa «Instalar».")
        case .notFound: String(localized: "macOS no encuentra el plist del demonio en la app.")
        }
        checks.append(Check(title: "Registro en el sistema", detail: registration, status: state == .enabled ? .ok : .failure))

        // 5. Respuesta XPC, mirando launchd antes y después: si el demonio arranca y termina
        //    sin atender, los arranques suben y la respuesta no llega.
        let before = await launchdState()
        let clock = ContinuousClock()
        let start = clock.now
        let version = await HelperClient.shared.installedVersion(timeout: .seconds(5))
        let elapsed = clock.now - start
        let after = await launchdState()

        if let version {
            let isCurrent = version == HelperConstants.helperVersion
            checks.append(Check(
                title: "Respuesta del asistente",
                detail: isCurrent
                    ? String(localized: "Versión \(version) en \(elapsed.formatted(.units(allowed: [.milliseconds], width: .abbreviated))).")
                    : String(localized: "Responde la versión \(version), pero esta app necesita la \(HelperConstants.helperVersion). Pulsa «Reinstalar»."),
                status: isCurrent ? .ok : .warning
            ))
        } else {
            checks.append(Check(
                title: "Respuesta del asistente",
                detail: String(localized: "No responde en 5 s."),
                status: .failure
            ))
        }
        checks.append(launchdCheck(before: before, after: after, responded: version != nil))
        return checks
    }

    /// Informe en texto para copiarlo y pegarlo en una incidencia.
    static func report(_ checks: [Check]) -> String {
        checks.map { check in
            let mark = switch check.status {
            case .ok: "✓"
            case .warning: "!"
            case .failure: "✗"
            case .info: "·"
            }
            return "\(mark) \(check.title): \(check.detail)"
        }
        .joined(separator: "\n")
    }

    private static func launchdCheck(before: LaunchdState, after: LaunchdState, responded: Bool) -> Check {
        let title = String(localized: "Proceso en launchd")
        guard after.isLoaded else {
            return Check(title: title, detail: String(localized: "launchd no lo tiene cargado. Pulsa «Reinstalar»."), status: .failure)
        }
        let runs = after.runs ?? 0
        let summary = String(localized: "Estado «\(after.state ?? "?")» · \(runs) arranques · última salida \(after.lastExitCode ?? "—")")

        let relaunched = (after.runs ?? 0) > (before.runs ?? 0)
        if !responded, relaunched || (after.pid == nil && runs >= 5) {
            return Check(
                title: title,
                detail: String(localized: "\(summary). launchd lo arranca pero termina sin atender a la app: el binario registrado no escucha en su servicio. Pulsa «Reinstalar» con esta versión de MaCleaner."),
                status: .failure
            )
        }
        if let pid = after.pid {
            return Check(title: title, detail: String(localized: "En marcha (pid \(pid)) · \(summary)"), status: .ok)
        }
        return Check(title: title, detail: String(localized: "\(summary). Se arranca al conectarse la app y se cierra solo tras unos minutos sin uso."), status: .info)
    }

    private static func launchdState() async -> LaunchdState {
        guard let output = try? await ProcessRunner.run(
            "/bin/launchctl",
            arguments: ["print", "system/\(HelperConstants.machServiceName)"]
        ), output.succeeded else {
            return LaunchdState()
        }
        var result = LaunchdState(isLoaded: true)
        // Solo las claves del primer nivel (un tabulador): las anidadas son de los endpoints.
        for line in output.output.split(separator: "\n") where line.hasPrefix("\t") && !line.hasPrefix("\t\t") {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " = ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = String(parts[1])
            switch parts[0] {
            case "state": result.state = value
            case "runs": result.runs = Int(value)
            case "last exit code": result.lastExitCode = value
            case "pid": result.pid = Int(value)
            default: break
            }
        }
        return result
    }

    private static func teamIdentifier(ofFileAt path: String) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
#endif
