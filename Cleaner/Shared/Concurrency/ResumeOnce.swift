import Synchronization

/// Envuelve una `CheckedContinuation` y garantiza que se reanuda exactamente una vez.
///
/// Las APIs basadas en callbacks (NSXPCConnection, PhotoKit) pueden invocar más de un
/// callback para la misma petición; por ejemplo, el *error handler* del proxy XPC y el
/// bloque de respuesta. Reanudar dos veces una continuación es un error fatal.
nonisolated final class ResumeOnce<Value: Sendable, Failure: Error>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, Failure>?>

    init(_ continuation: CheckedContinuation<Value, Failure>) {
        self.continuation = Mutex(continuation)
    }

    func resume(with result: Result<Value, Failure>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }

    func resume(returning value: Value) {
        resume(with: .success(value))
    }

    func resume(throwing error: Failure) {
        resume(with: .failure(error))
    }
}
