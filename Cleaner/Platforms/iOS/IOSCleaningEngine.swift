#if os(iOS)
import Foundation

/// Motor de iOS / iPadOS: une la Fototeca y las carpetas concedidas por el usuario.
///
/// El sandbox impide ver los datos de otras apps o del sistema. Lo que sí está al alcance:
/// la Fototeca (PhotoKit), las carpetas que el usuario elige en Archivos y pedir a iOS que
/// vacíe la parte purgable de «Datos del sistema» (`PurgeableSpaceReclaimer`).
nonisolated struct IOSCleaningEngine: CleaningEngine {
    /// Fototeca y carpetas (duplicados, capturas, vídeos, iCloud Drive, archivos grandes…).
    /// Desactivadas: en dispositivos reales su análisis no terminaba. Con `false` la app se
    /// queda en la basura del sistema, que es lo que funciona; el código sigue aquí para
    /// retomarlo midiendo en un dispositivo.
    static let includesPhotosAndFiles = false

    private let photos = PhotoLibraryEngine()
    private let files = FilesEngine()

    var supportedCategories: [CleaningCategory] {
        guard Self.includesPhotosAndFiles else { return [.systemData, .ownAppCache] }
        return [.systemData, .ownAppCache] + photos.supportedCategories + FilesEngine.categories
    }

    @concurrent
    func scan(categories: Set<CleaningCategory>, progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary {
        let clock = ContinuousClock()
        let start = clock.now
        let metrics = ScanMetrics()
        var items: [ScanItem] = []
        var inaccessible: Set<CleaningCategory> = []

        // Si no hay acceso a Fotos, se siguen analizando las carpetas (y al revés).
        let photoCategories = categories.intersection(photos.supportedCategories)
        let fileCategories = categories.intersection(FilesEngine.categories)

        // Fotos y carpetas van en paralelo: antes las carpetas esperaban a que terminase la
        // búsqueda de duplicados y parecía que nunca acababan.
        async let photoResult = Self.scanPhotos(photos, categories: photoCategories, progress: progress, metrics: metrics)
        async let fileResult = Self.scanFiles(files, categories: fileCategories, progress: progress, metrics: metrics)

        if categories.contains(.systemData) {
            progress.yield(.started(.systemData))
            let item = SystemDataScanner.item()
            if let item { items.append(item) }
            progress.yield(.finished(.systemData, bytes: item?.reclaimableBytes ?? 0))
        }

        if categories.contains(.ownAppCache) {
            progress.yield(.started(.ownAppCache))
            let own = OwnCacheScanner.items(metrics: metrics)
            items += own
            progress.yield(.finished(.ownAppCache, bytes: own.reduce(0) { $0 + $1.reclaimableBytes }))
        }

        let (photoItems, photosDenied) = try await photoResult
        items += photoItems
        if photosDenied { inaccessible.formUnion(photoCategories) }

        if let found = try await fileResult {
            items += found
        } else if !fileCategories.isEmpty {
            inaccessible.formUnion(fileCategories)
        }
        let entries = metrics.snapshot.entriesVisited

        return ScanSummary(
            items: items.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            entriesVisited: entries,
            duration: clock.now - start,
            inaccessibleCategories: inaccessible
        )
    }

    /// Fototeca: devuelve los elementos y si faltó el permiso.
    @concurrent
    private static func scanPhotos(
        _ engine: PhotoLibraryEngine,
        categories: Set<CleaningCategory>,
        progress: AsyncStream<ScanProgress>.Continuation,
        metrics: ScanMetrics
    ) async throws -> ([ScanItem], Bool) {
        guard !categories.isEmpty else { return ([], false) }
        do {
            let summary = try await engine.scan(categories: categories, progress: progress, metrics: metrics)
            return (summary.items, false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            categories.forEach { progress.yield(.finished($0, bytes: 0)) }
            return ([], true)
        }
    }

    /// Carpetas concedidas: `nil` si no hay ninguna.
    @concurrent
    private static func scanFiles(
        _ engine: FilesEngine,
        categories: Set<CleaningCategory>,
        progress: AsyncStream<ScanProgress>.Continuation,
        metrics: ScanMetrics
    ) async throws -> [ScanItem]? {
        guard !categories.isEmpty else { return [] }
        guard let found = try await engine.scan(categories: categories, progress: progress, metrics: metrics) else {
            categories.forEach { progress.yield(.finished($0, bytes: 0)) }
            return nil
        }
        return found
    }

    /// iOS limpia por grupos (Fototeca, archivos, purga) y no informa elemento a elemento.
    @concurrent
    func clean(_ items: [ScanItem], progress: AsyncStream<CleaningProgress>.Continuation) async throws -> CleaningReport {
        let photoItems = items.filter { $0.removal == .photoLibrary }
        let purgeItems = items.filter { $0.removal == .systemPurge }
        let fileItems = items.filter { $0.removal != .photoLibrary && $0.removal != .systemPurge }

        var reports: [CleaningReport] = []
        if !photoItems.isEmpty { reports.append(try await photos.clean(photoItems)) }
        if !fileItems.isEmpty { reports.append(await files.clean(fileItems)) }
        // La purga va al final: aprovecha el espacio que acaba de liberarse para apretar más.
        if !purgeItems.isEmpty { reports.append(await SystemDataScanner.purge()) }

        return CleaningReport(
            reclaimedBytes: reports.reduce(0) { $0 + $1.reclaimedBytes },
            trashedBytes: reports.reduce(0) { $0 + $1.trashedBytes },
            failures: reports.flatMap(\.failures),
            photosMovedToRecentlyDeleted: reports.reduce(0) { $0 + $1.photosMovedToRecentlyDeleted }
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

#if os(iOS)
/// «Datos del sistema» purgables: el único trozo de los datos del sistema que una app puede
/// hacer desaparecer, pidiéndole a iOS el espacio para que lo purgue él.
nonisolated enum SystemDataScanner {
    static let itemID = "ios-system-data-purgeable"

    /// Un único elemento con lo que iOS dice que es purgable ahora mismo.
    static func item() -> ScanItem? {
        guard let usage = DiskUsage.current(), usage.purgeableBytes > 0 else { return nil }
        return ScanItem(
            id: itemID,
            displayName: "Cachés y temporales del sistema",
            location: "iOS › Datos del sistema",
            category: .systemData,
            allocatedBytes: usage.purgeableBytes,
            reclaimableBytes: usage.purgeableBytes,
            lastModified: nil,
            risk: .safe,
            reason: "iOS los marca como prescindibles y los vuelve a crear si hacen falta. La cifra es la estimación de iOS: puede liberar algo más o algo menos.",
            removal: .systemPurge,
            detail: "Purga por oleadas · 1–5 min"
        )
    }

    /// Ejecuta la purga y la traduce a un informe de limpieza.
    static func purge() async -> CleaningReport {
        do {
            let outcome = try await PurgeableSpaceReclaimer.run(target: nil)
            var failures: [String] = []
            if !outcome.completed {
                failures.append("Datos del sistema: la purga se detuvo antes de terminar porque MaCleaner dejó de estar en pantalla. Vuelve a intentarlo sin salir de la app.")
            } else if outcome.freedBytes == 0 {
                failures.append("Datos del sistema: iOS no ha liberado nada esta vez. Suele pasar justo después de otra purga o de reiniciar; prueba de nuevo más tarde.")
            }
            return CleaningReport(reclaimedBytes: outcome.freedBytes, trashedBytes: 0, failures: failures)
        } catch {
            return CleaningReport(reclaimedBytes: 0, trashedBytes: 0, failures: ["Datos del sistema: \(error.localizedDescription)"])
        }
    }
}
#endif
