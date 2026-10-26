#if os(iOS)
import BackgroundTasks
import Foundation
import Synchronization

/// Permite que el análisis siga si el usuario sale de la app (`BGContinuedProcessingTask`,
/// iOS 26). El sistema muestra el progreso en una Live Activity, desde la que también se
/// puede cancelar.
///
/// Si iOS no concede la tarea (no la admite o hay demasiadas en curso), el análisis sigue
/// igual que antes: con la pantalla activa y la app delante.
nonisolated final class BackgroundScanSession: Sendable {
    static let shared = BackgroundScanSession()

    /// Debe encajar con `BGTaskSchedulerPermittedIdentifiers` del Info.plist
    /// (`$(PRODUCT_BUNDLE_IDENTIFIER).continued.*`).
    static let identifier = (Bundle.main.bundleIdentifier ?? "MaCleaner") + ".continued.scan"

    /// `BGContinuedProcessingTask` no está marcada como `Sendable`, pero sus métodos se pueden
    /// llamar desde cualquier hilo; siempre se accede a ella bajo el `Mutex`.
    nonisolated private struct TaskBox: @unchecked Sendable {
        let task: BGContinuedProcessingTask
    }

    nonisolated private struct State: Sendable {
        var task: TaskBox?
        /// Hay un análisis en curso que quiere la tarea.
        var isActive = false
        /// El análisis terminó antes de que iOS entregase la tarea.
        var pendingCompletion: Bool?
        var onExpire: (@Sendable () -> Void)?
        var lastReportedPermille = -1
        /// Número del análisis actual: uno anterior que acabe tarde no cierra la tarea del nuevo.
        var generation = 0
    }

    private let state = Mutex(State())

    /// Se llama una vez al arrancar la app, como exige `BGTaskScheduler`.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            BackgroundScanSession.shared.attach(task)
        }
    }

    /// Pide a iOS que deje seguir el análisis en segundo plano. `onExpire` se llama si el usuario
    /// lo cancela desde la Live Activity o si iOS lo interrumpe. Devuelve el número que hay que
    /// pasar a `finish`.
    @discardableResult
    func begin(onExpire: @escaping @Sendable () -> Void) -> Int {
        let (previous, generation) = state.withLock { state in
            let previous = state.task
            state = State(isActive: true, onExpire: onExpire, generation: state.generation + 1)
            return (previous, state.generation)
        }
        // Un análisis anterior que no llegó a cerrarse se da por terminado.
        previous?.task.setTaskCompleted(success: false)

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier,
            title: String(localized: "Analizando con MaCleaner"),
            subtitle: String(localized: "Preparando…")
        )
        // Si no puede empezar ya, no tiene sentido ponerla en cola: el análisis ya está en marcha.
        request.strategy = .fail
        BGTaskScheduler.shared.submitTaskRequest(request) { [weak self] error in
            guard error != nil, let self else { return }
            state.withLock { state in
                if state.generation == generation { state.isActive = false }
            }
        }
        return generation
    }

    /// Actualiza la Live Activity. `fraction` va de 0 a 1.
    func update(fraction: Double, subtitle: String) {
        let permille = Int((min(max(fraction, 0), 1) * 1000).rounded())
        let box: TaskBox? = state.withLock { state in
            // Solo se informa cuando cambia de verdad, para no saturar al sistema.
            guard state.isActive, permille != state.lastReportedPermille else { return nil }
            state.lastReportedPermille = permille
            return state.task
        }
        guard let task = box?.task else { return }
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = Int64(permille)
        task.updateTitle(task.title, subtitle: subtitle)
    }

    /// Cierra la tarea al terminar o cancelar el análisis número `generation`.
    func finish(generation: Int, success: Bool) {
        let box: TaskBox? = state.withLock { state in
            guard state.isActive, state.generation == generation else { return nil }
            state.isActive = false
            state.onExpire = nil
            if state.task == nil { state.pendingCompletion = success }
            defer { state.task = nil }
            return state.task
        }
        guard let task = box?.task else { return }
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: success)
    }

    private func attach(_ task: BGContinuedProcessingTask) {
        let box = TaskBox(task: task)
        let completion: Bool? = state.withLock { state in
            if let pending = state.pendingCompletion {
                state.pendingCompletion = nil
                return pending
            }
            guard state.isActive else { return false }
            state.task = box
            return nil
        }
        if let completion {
            task.setTaskCompleted(success: completion)
            return
        }

        task.progress.totalUnitCount = 1000
        task.expirationHandler = { [weak self] in
            guard let self else { return }
            let onExpire: (@Sendable () -> Void)? = state.withLock { state in
                defer {
                    state.isActive = false
                    state.task = nil
                    state.onExpire = nil
                }
                return state.onExpire
            }
            onExpire?()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
