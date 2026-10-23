import Synchronization

/// Acumulador de métricas compartido entre tareas hijas.
///
/// Usa `Mutex` (framework Synchronization) en lugar de un actor: las actualizaciones
/// son diminutas y frecuentes, y un `await` por cada lote de archivos añadiría
/// saltos de ejecutor innecesarios.
nonisolated final class ScanMetrics: Sendable {
    nonisolated struct Snapshot: Sendable {
        var entriesVisited = 0
        var allocatedBytes: Int64 = 0
        var reclaimableBytes: Int64 = 0
    }

    private let state = Mutex(Snapshot())

    func record(entries: Int, allocated: Int64, reclaimable: Int64) {
        state.withLock {
            $0.entriesVisited += entries
            $0.allocatedBytes += allocated
            $0.reclaimableBytes += reclaimable
        }
    }

    var snapshot: Snapshot {
        state.withLock { $0 }
    }
}
