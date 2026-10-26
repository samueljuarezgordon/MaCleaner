#if os(iOS)
import Foundation
import os

/// Analiza las carpetas concedidas por el usuario: copias locales de iCloud Drive que se
/// pueden liberar, archivos grandes y comprimidos o instaladores.
nonisolated struct FilesEngine: Sendable {
    /// Archivos locales a partir de este tamaño se proponen como "grandes".
    static let largeFileThreshold: Int64 = 100 * 1024 * 1024
    /// Copias de iCloud Drive menores que esto no se listan, para no llenar la lista de ruido.
    static let minimumCloudFileBytes: Int64 = 1024 * 1024

    static let categories: [CleaningCategory] = [.iCloudDriveDownloads, .largeFiles, .compressedArchives]

    private static let archiveExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "ipa", "dmg", "pkg", "iso", "ipsw",
    ]

    fileprivate static let keys: [URLResourceKey] = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .totalFileSizeKey, .fileSizeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .contentModificationDateKey,
    ]

    /// Subcarpetas que se recorren a la vez. En iCloud Drive cada consulta de atributos pasa por
    /// el proveedor de archivos del sistema; en serie, con miles de archivos, no acababa nunca.
    private static let maxConcurrentFolders = 8

    private static let logger = Logger(subsystem: "MaCleaner", category: "Archivos")

    /// `nil` si el usuario no ha concedido ninguna carpeta.
    @concurrent
    func scan(
        categories: Set<CleaningCategory>,
        progress: AsyncStream<ScanProgress>.Continuation,
        metrics: ScanMetrics
    ) async throws -> [ScanItem]? {
        let folders = FolderAccessStore.folders()
        guard !folders.isEmpty else { return nil }
        let wanted = Self.categories.filter(categories.contains)
        wanted.forEach { progress.yield(.started($0)) }

        var items: [ScanItem] = []
        for folder in folders {
            try Task.checkCancellation()
            let clock = ContinuousClock()
            let start = clock.now
            let before = metrics.snapshot.entriesVisited
            let didStart = folder.startAccessingSecurityScopedResource()
            defer { if didStart { folder.stopAccessingSecurityScopedResource() } }

            items += try await Self.scan(folder: folder, metrics: metrics, progress: progress)

            let visited = metrics.snapshot.entriesVisited - before
            Self.logger.info("\(folder.lastPathComponent, privacy: .public): \(visited) elementos en \((clock.now - start).formatted(), privacy: .public)")
            let snapshot = metrics.snapshot
            progress.yield(.metrics(entriesVisited: snapshot.entriesVisited, bytes: snapshot.allocatedBytes))
        }

        items = items.filter { categories.contains($0.category) }
        for category in wanted {
            progress.yield(.finished(category, bytes: items.filter { $0.category == category }.reduce(0) { $0 + $1.reclaimableBytes }))
        }
        return items
    }

    /// Recorre `folder`: sus archivos directos aquí y cada subcarpeta en paralelo.
    private static func scan(folder: URL, metrics: ScanMetrics, progress: AsyncStream<ScanProgress>.Continuation) async throws -> [ScanItem] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys + [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var topLevel = Listing()
        var subfolders: [URL] = []
        for child in children {
            let kind = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if kind?.isDirectory == true, kind?.isPackage != true {
                subfolders.append(child)
                topLevel.folderNames[folder.path, default: []].insert(child.lastPathComponent.lowercased())
            } else {
                topLevel.add(child)
            }
            metrics.record(entries: 1, allocated: 0, reclaimable: 0)
        }
        var items = classify(topLevel, folder: folder, metrics: metrics)

        items += try await withThrowingTaskGroup(of: [ScanItem].self) { group in
            var pending = subfolders.makeIterator()
            for _ in 0..<maxConcurrentFolders {
                guard let subfolder = pending.next() else { break }
                group.addTask { try Self.scanTree(subfolder, folder: folder, metrics: metrics, progress: progress) }
            }
            var found: [ScanItem] = []
            while let result = try await group.next() {
                found += result
                if let subfolder = pending.next() {
                    group.addTask { try Self.scanTree(subfolder, folder: folder, metrics: metrics, progress: progress) }
                }
            }
            return found
        }
        return items
    }

    /// Archivos y nombres de carpeta encontrados en un recorrido.
    nonisolated private struct Listing {
        var files: [(url: URL, values: URLResourceValues)] = []
        /// Nombres de carpetas por directorio, para saber si un comprimido ya está descomprimido.
        var folderNames: [String: Set<String>] = [:]

        mutating func add(_ url: URL) {
            guard let values = try? url.resourceValues(forKeys: Set(FilesEngine.keys)) else { return }
            if values.isRegularFile == true {
                files.append((url, values))
            } else {
                folderNames[url.deletingLastPathComponent().path, default: []].insert(url.lastPathComponent.lowercased())
            }
        }
    }

    /// Recorre una subcarpeta entera (síncrono: lo ejecuta una tarea del grupo).
    private static func scanTree(_ root: URL, folder: URL, metrics: ScanMetrics, progress: AsyncStream<ScanProgress>.Continuation) throws -> [ScanItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var listing = Listing()
        var visited = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            listing.add(url)
            visited += 1
            // Se cuenta por lotes para no bloquear el contador compartido en cada archivo.
            if visited.isMultiple(of: 250) {
                metrics.record(entries: 250, allocated: 0, reclaimable: 0)
                let snapshot = metrics.snapshot
                progress.yield(.metrics(entriesVisited: snapshot.entriesVisited, bytes: snapshot.allocatedBytes))
            }
        }
        metrics.record(entries: visited % 250, allocated: 0, reclaimable: 0)
        return classify(listing, folder: folder, metrics: metrics)
    }

    /// Decide qué se propone de cada archivo encontrado.
    private static func classify(_ listing: Listing, folder: URL, metrics: ScanMetrics) -> [ScanItem] {
        let files = listing.files
        let folderNames = listing.folderNames
        var items: [ScanItem] = []
        for (url, values) in files {
            // En iCloud Drive y otros proveedores de Archivos, iOS a menudo no informa del
            // tamaño asignado: se usa entonces el tamaño lógico.
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let logical = Int64(values.totalFileSize ?? values.fileSize ?? 0)
            let bytes = allocated > 0 ? allocated : logical
            metrics.record(entries: 0, allocated: bytes, reclaimable: bytes)
            guard bytes > 0 else { continue }

            let ext = url.pathExtension.lowercased()
            let isDownloadedCloudCopy = values.isUbiquitousItem == true
                && values.ubiquitousItemDownloadingStatus == .current

            if isDownloadedCloudCopy, bytes >= minimumCloudFileBytes {
                items.append(item(
                    url, folder: folder, values: values, bytes: bytes, category: .iCloudDriveDownloads, risk: .safe,
                    reason: "Copia descargada de un archivo que está en iCloud Drive. Al liberarla, el archivo sigue en iCloud y en tus otros dispositivos.",
                    removal: .evictFromDevice
                ))
            } else if archiveExtensions.contains(ext) {
                let base = url.deletingPathExtension().lastPathComponent.lowercased()
                let siblings = folderNames[url.deletingLastPathComponent().path] ?? []
                let (risk, reason): (RiskLevel, String) = siblings.contains(base)
                    ? (.moderate, "Ya existe la carpeta descomprimida «\(url.deletingPathExtension().lastPathComponent)» al lado. Comprueba que está completa antes de borrar el comprimido.")
                    : (.high, "Archivo comprimido o instalador: puede ser la única copia de su contenido.")
                items.append(item(url, folder: folder, values: values, bytes: bytes, category: .compressedArchives, risk: risk, reason: reason, removal: .moveToTrash))
            } else if bytes >= largeFileThreshold {
                let age = values.contentModificationDate.map { " Lo modificaste \($0.formatted(.relative(presentation: .named)))." } ?? ""
                items.append(item(
                    url, folder: folder, values: values, bytes: bytes, category: .largeFiles, risk: .high,
                    reason: "Archivo personal.\(age) Decide tú si lo necesitas.",
                    removal: .moveToTrash
                ))
            }
        }
        return items
    }

    private static func item(
        _ url: URL,
        folder: URL,
        values: URLResourceValues,
        bytes: Int64,
        category: CleaningCategory,
        risk: RiskLevel,
        reason: String,
        removal: RemovalMethod
    ) -> ScanItem {
        // Ubicación legible: «Descargas/Proyectos» en lugar de la ruta del contenedor.
        let parent = url.deletingLastPathComponent().path
        let relative = parent.hasPrefix(folder.path) ? String(parent.dropFirst(folder.path.count)) : ""
        return ScanItem(
            id: url.path,
            displayName: url.lastPathComponent,
            location: folder.lastPathComponent + relative,
            category: category,
            allocatedBytes: bytes,
            reclaimableBytes: bytes,
            lastModified: values.contentModificationDate,
            risk: risk,
            reason: reason,
            removal: removal
        )
    }

    // MARK: - Limpieza

    @concurrent
    func clean(_ items: [ScanItem]) async -> CleaningReport {
        await FolderAccessStore.withAccessToAll {
            var reclaimed: Int64 = 0
            var trashed: Int64 = 0
            var failures: [String] = []
            let fileManager = FileManager.default

            for item in items {
                let url = URL(fileURLWithPath: item.id)
                do {
                    switch item.removal {
                    case .evictFromDevice:
                        try fileManager.evictUbiquitousItem(at: url)
                        reclaimed += item.reclaimableBytes
                    case .moveToTrash:
                        // En iCloud Drive y En mi iPhone va a «Eliminados recientemente» de Archivos.
                        try fileManager.trashItem(at: url, resultingItemURL: nil)
                        trashed += item.reclaimableBytes
                    case .delete:
                        try fileManager.removeItem(at: url)
                        reclaimed += item.reclaimableBytes
                    default:
                        continue
                    }
                } catch {
                    let hint = item.removal == .moveToTrash
                        ? " Si esta ubicación no tiene «Eliminados recientemente», activa «No usar la Papelera» al limpiar."
                        : ""
                    failures.append("\(item.displayName): \(error.localizedDescription)\(hint)")
                }
            }
            return CleaningReport(reclaimedBytes: reclaimed, trashedBytes: trashed, failures: failures)
        }
    }
}
#endif
