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
        [.ownAppCache] + photos.supportedCategories + FilesEngine.categories
    }

    @concurrent
    func scan(categories: Set<CleaningCategory>, progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary {
        let clock = ContinuousClock()
        let start = clock.now
        let metrics = ScanMetrics()
        var items: [ScanItem] = []
        var entries = 0
        var inaccessible: Set<CleaningCategory> = []

        // Si no hay acceso a Fotos, se siguen analizando las carpetas (y al revés).
        let photoCategories = categories.intersection(photos.supportedCategories)
        let fileCategories = categories.intersection(FilesEngine.categories)

        do {
            let summary = try await photos.scan(categories: photoCategories, progress: progress)
            items += summary.items
            entries += summary.entriesVisited
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            inaccessible.formUnion(photoCategories)
            photoCategories.forEach { progress.yield(.finished($0, bytes: 0)) }
        }

        if categories.contains(.ownAppCache) {
            progress.yield(.started(.ownAppCache))
            let own = OwnCacheScanner.items(metrics: metrics)
            items += own
            progress.yield(.finished(.ownAppCache, bytes: own.reduce(0) { $0 + $1.reclaimableBytes }))
        }

        if !fileCategories.isEmpty {
            if let found = try await files.scan(categories: fileCategories, progress: progress, metrics: metrics) {
                items += found
            } else {
                inaccessible.formUnion(fileCategories)
                fileCategories.forEach { progress.yield(.finished($0, bytes: 0)) }
            }
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

#if os(iOS)
/// Limpieza interna: cachés y temporales de la propia app (`cachesDirectory` y `tmp`).
nonisolated enum OwnCacheScanner {
    static func items(metrics: ScanMetrics) -> [ScanItem] {
        let fileManager = FileManager.default
        var roots: [(url: URL, name: String)] = [(fileManager.temporaryDirectory, "Temporales")]
        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            roots.append((caches, "Cachés"))
        }

        var items: [ScanItem] = []
        for root in roots {
            let children = (try? fileManager.contentsOfDirectory(at: root.url, includingPropertiesForKeys: nil)) ?? []
            // El archivo de relleno de la purga nunca se lista: se gestiona aparte.
            for child in children where child.lastPathComponent != PurgeableSpaceReclaimer.reservationURL.lastPathComponent {
                let bytes = size(of: child)
                metrics.record(entries: 1, allocated: bytes, reclaimable: bytes)
                guard bytes > 0 else { continue }
                items.append(ScanItem(
                    id: child.path,
                    displayName: child.lastPathComponent,
                    location: "MaCleaner › \(root.name)",
                    category: .ownAppCache,
                    allocatedBytes: bytes,
                    reclaimableBytes: bytes,
                    lastModified: (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                    risk: .safe,
                    reason: "Archivo temporal de MaCleaner. La app lo vuelve a crear si lo necesita.",
                    removal: .delete
                ))
            }
        }
        return items
    }

    private static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else {
            return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
        while let file = enumerator?.nextObject() as? URL {
            let fileValues = try? file.resourceValues(forKeys: keys)
            total += Int64(fileValues?.totalFileAllocatedSize ?? fileValues?.fileSize ?? 0)
        }
        return total
    }
}
#endif
