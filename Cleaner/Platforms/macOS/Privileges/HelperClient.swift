#if os(macOS)
import Foundation

/// Cliente XPC del demonio privilegiado.
///
/// Es un `actor` porque `NSXPCConnection` no es `Sendable`: el actor es el único dueño
/// de la conexión y la reconstruye si se invalida.
actor HelperClient {
    static let shared = HelperClient()

    enum ClientError: LocalizedError {
        case unsignedApplication
        case invalidProxy
        case timedOut(Duration)

        var errorDescription: String? {
            switch self {
            case .unsignedApplication:
                String(localized: "La app no está firmada con un certificado de equipo; no es posible validar al demonio.")
            case .invalidProxy:
                String(localized: "El demonio no expone la interfaz esperada.")
            case .timedOut(let limit):
                String(localized: "El asistente privilegiado no respondió en \(limit.formatted(.units(allowed: [.minutes, .seconds], width: .wide))). Reinstálalo en Mantenimiento y permisos.")
            }
        }
    }

    /// Plazos máximos de cada operación. Son generosos: solo cortan esperas que nunca acabarían.
    enum Timeout {
        static let version: Duration = .seconds(10)
        static let removeItems: Duration = .seconds(10 * 60)
        static let thinSnapshots: Duration = .seconds(30 * 60)
        static let launchItem: Duration = .seconds(2 * 60)
    }

    private var connection: NSXPCConnection?

    // MARK: - Operaciones

    func version() async throws -> String {
        try await call(timeout: Timeout.version) { proxy, once in
            proxy.version { once.resume(returning: $0) }
        }
    }

    /// Versión del demonio en ejecución, o `nil` si no responde en `timeout`.
    func installedVersion(timeout: Duration = .seconds(3)) async -> String? {
        // Carrera sin estructura: una llamada XPC colgada no atiende a la cancelación, así
        // que un TaskGroup esperaría a que terminase. Gana quien reanude primero.
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(continuation)
            Task { once.resume(returning: try? await self.version()) }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(returning: nil)
            }
        }
    }

    func removeItems(atPaths paths: [String]) async throws -> (removed: [String], failures: [String]) {
        try await call(timeout: Timeout.removeItems) { proxy, once in
            proxy.removeItems(atPaths: paths) { removed, failures in
                once.resume(returning: (removed, failures))
            }
        }
    }

    func thinLocalSnapshots() async throws -> ProcessOutput {
        try await call(timeout: Timeout.thinSnapshots) { proxy, once in
            proxy.thinLocalSnapshots { exitCode, output in
                once.resume(returning: ProcessOutput(exitCode: exitCode, output: output))
            }
        }
    }

    func removeLaunchItem(atPath path: String) async throws -> (removed: Bool, message: String) {
        try await call(timeout: Timeout.launchItem) { proxy, once in
            proxy.removeLaunchItem(atPath: path) { removed, message in
                once.resume(returning: (removed, message))
            }
        }
    }

    // MARK: - Conexión

    /// Puente entre el estilo *reply block* de NSXPC y async/await, con un plazo máximo.
    ///
    /// Si el demonio no escucha, launchd lo relanza sin fin y el mensaje nunca recibe ni
    /// respuesta ni error: sin plazo, la espera no acabaría nunca.
    private func call<Value: Sendable>(
        timeout: Duration,
        _ body: (any HelperProtocol, ResumeOnce<Value, any Error>) -> Void
    ) async throws -> Value {
        var deadline: Task<Void, Never>?
        defer { deadline?.cancel() }
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                deadline = Task {
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    once.resume(throwing: ClientError.timedOut(timeout))
                }
                send(body, once: once)
            }
        } catch ClientError.timedOut(let limit) {
            // La conexión puede haberse quedado atascada: la siguiente llamada abre otra.
            discardCurrentConnection()
            throw ClientError.timedOut(limit)
        }
    }

    private func send<Value: Sendable>(
        _ body: (any HelperProtocol, ResumeOnce<Value, any Error>) -> Void,
        once: ResumeOnce<Value, any Error>
    ) {
        do {
            let connection = try currentConnection()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(throwing: error)
            }
            guard let helper = proxy as? any HelperProtocol else {
                throw ClientError.invalidProxy
            }
            body(helper, once)
        } catch {
            once.resume(throwing: error)
        }
    }

    private func currentConnection() throws -> NSXPCConnection {
        if let connection { return connection }

        // Validación inversa: solo se habla con un demonio firmado por nuestro mismo equipo.
        guard let requirement = CodeSigningValidator.requirement(
            forIdentifier: HelperConstants.helperBundleIdentifier
        ) else {
            throw ClientError.unsignedApplication
        }

        let connection = NSXPCConnection(
            machServiceName: HelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)

        let identifier = ObjectIdentifier(connection)
        connection.invalidationHandler = { [weak self] in
            Task { await self?.discardConnection(identifier) }
        }
        connection.interruptionHandler = { [weak self] in
            Task { await self?.discardConnection(identifier) }
        }
        connection.resume()

        self.connection = connection
        return connection
    }

    private func discardCurrentConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func discardConnection(_ identifier: ObjectIdentifier) {
        guard let connection, ObjectIdentifier(connection) == identifier else { return }
        connection.invalidate()
        self.connection = nil
    }
}
#endif
