#if os(macOS)
import Foundation
import Synchronization

/// Algo que medir: un directorio (se recorre entero) o un archivo ya leído.
nonisolated struct MeasureTarget: Sendable {
    let path: String
    let name: String
    /// Si no es `nil`, es un archivo y no hace falta recorrerlo.
    let file: DirectoryEntry?

    static func directory(_ path: String, name: String? = nil) -> MeasureTarget {
        MeasureTarget(path: path, name: name ?? (path as NSString).lastPathComponent, file: nil)
    }
}

/// Estado compartido por todos los recolectores durante un escaneo.
nonisolated final class MacScanContext: Sendable {
    let scanner = BulkDirectoryScanner()
    let metrics = ScanMetrics()
    let apps: InstalledAppIndex
    let home = NSHomeDirectory()
    private let progress: AsyncStream<ScanProgress>.Continuation
    private let state = Mutex(State())

    private struct State {
        var inaccessible: Set<CleaningCategory> = []
        var foundBytes: Int64 = 0
    }

    /// Elementos menores que esto no se listan, para no llenar la lista de ruido.
    static let minimumItemBytes: Int64 = 50 * 1024

    init(apps: InstalledAppIndex, progress: AsyncStream<ScanProgress>.Continuation) {
        self.apps = apps
        self.progress = progress
    }

    var inaccessibleCategories: Set<CleaningCategory> {
        state.withLock { $0.inaccessible }
    }

    // MARK: - Progreso

    func started(_ category: CleaningCategory) {
        progress.yield(.started(category))
    }

    func finished(_ category: CleaningCategory, items: [ScanItem]) {
        let bytes = items.filter { $0.category == category }.reduce(0) { $0 + $1.reclaimableBytes }
        let total = state.withLock {
            $0.foundBytes += bytes
            return $0.foundBytes
        }
        progress.yield(.finished(category, bytes: bytes))
        progress.yield(.metrics(entriesVisited: metrics.snapshot.entriesVisited, bytes: total))
    }

    func reportMetrics() {
        let found = state.withLock { $0.foundBytes }
        progress.yield(.metrics(entriesVisited: metrics.snapshot.entriesVisited, bytes: found))
    }

    // MARK: - Lectura

    /// Lista un directorio. Si TCC lo impide, marca la categoría como inaccesible.
    func entries(in path: String, for category: CleaningCategory) -> [DirectoryEntry] {
        do {
            return try scanner.entries(in: path)
        } catch {
            if error.isPermissionDenied {
                state.withLock { _ = $0.inaccessible.insert(category) }
            }
            return []
        }
    }

    func measure(_ target: MeasureTarget, options: TraversalOptions = TraversalOptions()) async throws -> TreeUsage {
        if let file = target.file {
            metrics.record(entries: 1, allocated: file.allocatedBytes, reclaimable: file.reclaimableBytes)
            return TreeUsage(
                entries: 1,
                allocatedBytes: file.allocatedBytes,
                reclaimableBytes: file.reclaimableBytes,
                lastModified: file.modificationDate
            )
        }
        return try await scanner.measureTree(at: target.path, metrics: metrics, options: options)
    }

    /// Mide varios destinos en paralelo y construye un `ScanItem` por cada uno.
    func measureEach(
        _ targets: [MeasureTarget],
        options: TraversalOptions = TraversalOptions(),
        makeItem: @escaping @Sendable (MeasureTarget, TreeUsage) -> ScanItem?
    ) async throws -> [ScanItem] {
        try await withThrowingTaskGroup(of: ScanItem?.self) { group in
            for target in targets {
                group.addTask {
                    let usage = try await self.measure(target, options: options)
                    guard usage.allocatedBytes >= Self.minimumItemBytes else { return nil }
                    return makeItem(target, usage)
                }
            }
            var items: [ScanItem] = []
            for try await item in group {
                if let item { items.append(item) }
            }
            reportMetrics()
            return items
        }
    }

    // MARK: - Construcción de elementos

    func item(
        _ target: MeasureTarget,
        usage: TreeUsage,
        displayName: String? = nil,
        category: CleaningCategory,
        risk: RiskLevel,
        reason: String,
        removal: RemovalMethod,
        detail: String? = nil
    ) -> ScanItem {
        ScanItem(
            id: target.path,
            displayName: displayName ?? target.name,
            location: displayPath((target.path as NSString).deletingLastPathComponent),
            category: category,
            allocatedBytes: usage.allocatedBytes,
            reclaimableBytes: usage.reclaimableBytes,
            lastModified: usage.lastModified,
            risk: risk,
            reason: reason,
            removal: removal,
            detail: detail
        )
    }

    /// Ruta con `~` en lugar de la carpeta de inicio.
    func displayPath(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Nombre de la app si `name` es su identificador de bundle.
    func friendlyName(for name: String) -> String {
        apps.displayName(forBundleIdentifier: name) ?? name
    }
}

extension Date {
    /// "hace 8 meses", "ayer"…
    nonisolated var relativeDescription: String {
        formatted(.relative(presentation: .named))
    }

    nonisolated func isOlder(thanDays days: Int) -> Bool {
        timeIntervalSinceNow < -TimeInterval(days) * 86_400
    }
}
#endif
