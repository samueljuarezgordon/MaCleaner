#if os(iOS)
import Foundation

/// Motor de iOS / iPadOS: une la Fototeca y las carpetas concedidas por el usuario.
///
/// El sandbox impide ver los datos de otras apps o del sistema. Lo que sí está al alcance:
/// la Fototeca (PhotoKit), las carpetas que el usuario elige en Archivos y, con la acción de
/// mantenimiento de espacio purgable, pedir a iOS que vacíe sus cachés.
nonisolated struct IOSCleaningEngine: CleaningEngine {
    private let photos = PhotoLibraryEngine()
    private let files = FilesEngine()

    var supportedCategories: [CleaningCategory] {
        photos.supportedCategories + FilesEngine.categories
    }

    @concurrent
    func scan(progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary {
        let clock = ContinuousClock()
        let start = clock.now
        let metrics = ScanMetrics()
        var items: [ScanItem] = []
        var entries = 0
        var inaccessible: Set<CleaningCategory> = []

        // Si no hay acceso a Fotos, se siguen analizando las carpetas (y al revés).
        do {
            let summary = try await photos.scan(progress: progress)
            items += summary.items
            entries += summary.entriesVisited
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            inaccessible.formUnion(photos.supportedCategories)
            photos.supportedCategories.forEach { progress.yield(.finished($0, bytes: 0)) }
        }

        if let found = try await files.scan(progress: progress, metrics: metrics) {
            items += found
        } else {
            inaccessible.formUnion(FilesEngine.categories)
            FilesEngine.categories.forEach { progress.yield(.finished($0, bytes: 0)) }
        }
        entries += metrics.snapshot.entriesVisited

        return ScanSummary(
            items: items.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            entriesVisited: entries,
            duration: clock.now - start,
            inaccessibleCategories: inaccessible
        )
    }

    @concurrent
    func clean(_ items: [ScanItem]) async throws -> CleaningReport {
        let photoItems = items.filter { $0.removal == .photoLibrary }
        let fileItems = items.filter { $0.removal != .photoLibrary }

        var reports: [CleaningReport] = []
        if !photoItems.isEmpty { reports.append(try await photos.clean(photoItems)) }
        if !fileItems.isEmpty { reports.append(await files.clean(fileItems)) }

        return CleaningReport(
            reclaimedBytes: reports.reduce(0) { $0 + $1.reclaimedBytes },
            trashedBytes: reports.reduce(0) { $0 + $1.trashedBytes },
            failures: reports.flatMap(\.failures)
        )
    }
}
#endif
