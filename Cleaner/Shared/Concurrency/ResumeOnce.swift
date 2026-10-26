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

/// Espera a `operation`, pero deja de esperar en cuanto se cancela la tarea, aunque la
/// operación no atienda a la cancelación (una llamada XPC, un proceso, un borrado enorme).
/// La operación sigue en segundo plano; solo se abandona su resultado.
nonisolated func abandoningOnCancel<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let slot = AbandonSlot<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            slot.attach(once)
            Task {
                do {
                    once.resume(returning: try await operation())
                } catch {
                    once.resume(throwing: error)
                }
            }
        }
    } onCancel: {
        slot.cancel()
    }
}

/// Une la continuación con el aviso de cancelación, que puede llegar antes o después.
private nonisolated final class AbandonSlot<Value: Sendable>: Sendable {
    private let state = Mutex<(once: ResumeOnce<Value, any Error>?, isCancelled: Bool)>((nil, false))

    func attach(_ once: ResumeOnce<Value, any Error>) {
        let isCancelled = state.withLock { state in
            state.once = once
            return state.isCancelled
        }
        if isCancelled { once.resume(throwing: CancellationError()) }
    }

    func cancel() {
        let once = state.withLock { state in
            state.isCancelled = true
            return state.once
        }
        once?.resume(throwing: CancellationError())
    }
}
