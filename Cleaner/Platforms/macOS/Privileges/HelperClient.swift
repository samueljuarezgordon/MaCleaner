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

        var errorDescription: String? {
            switch self {
            case .unsignedApplication:
                "La app no está firmada con un certificado de equipo; no es posible validar al demonio."
            case .invalidProxy:
                "El demonio no expone la interfaz esperada."
            }
        }
    }

    private var connection: NSXPCConnection?

    // MARK: - Operaciones

    func version() async throws -> String {
        try await call { proxy, once in
            proxy.version { once.resume(returning: $0) }
        }
    }

    func removeItems(atPaths paths: [String]) async throws -> (removed: [String], failures: [String]) {
        try await call { proxy, once in
            proxy.removeItems(atPaths: paths) { removed, failures in
                once.resume(returning: (removed, failures))
            }
        }
    }

    func thinLocalSnapshots() async throws -> ProcessOutput {
        try await call { proxy, once in
            proxy.thinLocalSnapshots { exitCode, output in
                once.resume(returning: ProcessOutput(exitCode: exitCode, output: output))
            }
        }
    }

    func removeLaunchItem(atPath path: String) async throws -> (removed: Bool, message: String) {
        try await call { proxy, once in
            proxy.removeLaunchItem(atPath: path) { removed, message in
                once.resume(returning: (removed, message))
            }
        }
    }

    // MARK: - Conexión

    /// Puente entre el estilo *reply block* de NSXPC y async/await.
    private func call<Value: Sendable>(
        _ body: (any HelperProtocol, ResumeOnce<Value, any Error>) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
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

    private func discardConnection(_ identifier: ObjectIdentifier) {
        guard let connection, ObjectIdentifier(connection) == identifier else { return }
        connection.invalidate()
        self.connection = nil
    }
}
#endif
