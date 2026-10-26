import Foundation
import Synchronization

/// Termina el demonio tras un rato sin peticiones, para no dejar un proceso root vivo
/// sin necesidad. launchd lo vuelve a arrancar en cuanto la app se conecte de nuevo.
nonisolated final class IdleMonitor: Sendable {
    static let shared = IdleMonitor()

    /// Tiempo sin operaciones en curso tras el que el demonio termina.
    static let idleTimeout: TimeInterval = 120

    private struct State {
        var activeOperations = 0
        var lastActivity = Date.now
    }

    private let state = Mutex(State())

    /// Marca el inicio de una operación. Llama a `end()` cuando responda.
    func begin() {
        state.withLock {
            $0.activeOperations += 1
            $0.lastActivity = .now
        }
    }

    func end() {
        state.withLock {
            $0.activeOperations = max(0, $0.activeOperations - 1)
            $0.lastActivity = .now
        }
    }

    /// Comprueba cada 30 s si lleva `idleTimeout` sin trabajo y, si es así, termina.
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [self] in
            let isIdle = state.withLock {
                $0.activeOperations == 0 && Date.now.timeIntervalSince($0.lastActivity) >= Self.idleTimeout
            }
            if isIdle { exit(0) }
        }
        timer.resume()
        // El temporizador se cancela si se libera: vive tanto como el proceso.
        Self.timer.withLock { $0 = timer }
    }

    private static let timer = Mutex<(any DispatchSourceTimer)?>(nil)
}
