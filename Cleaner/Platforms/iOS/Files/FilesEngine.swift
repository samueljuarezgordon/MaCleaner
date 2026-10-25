#if os(iOS)
import Foundation

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

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .totalFileSizeKey, .fileSizeKey,
        .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .contentModificationDateKey,
    ]

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
            items += try FolderAccessStore.withAccess(to: folder) {
                try Self.scan(folder: folder, metrics: metrics)
            }
            let snapshot = metrics.snapshot
            progress.yield(.metrics(entriesVisited: snapshot.entriesVisited, bytes: items.reduce(0) { $0 + $1.reclaimableBytes }))
        }

        items = items.filter { categories.contains($0.category) }
        for category in wanted {
            progress.yield(.finished(category, bytes: items.filter { $0.category == category }.reduce(0) { $0 + $1.reclaimableBytes }))
        }
        return items
    }

    private static func scan(folder: URL, metrics: ScanMetrics) throws -> [ScanItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        // Nombres de carpetas por directorio, para saber si un comprimido ya está descomprimido.
        var folderNames: [String: Set<String>] = [:]
        var files: [(url: URL, values: URLResourceValues)] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isRegularFile == true {
                files.append((url, values))
            } else {
                folderNames[url.deletingLastPathComponent().path, default: []].insert(url.lastPathComponent.lowercased())
            }
        }

        var items: [ScanItem] = []
        for (url, values) in files {
            // En iCloud Drive y otros proveedores de Archivos, iOS a menudo no informa del
            // tamaño asignado: se usa entonces el tamaño lógico.
            let allocated = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            let logical = Int64(values.totalFileSize ?? values.fileSize ?? 0)
            let bytes = allocated > 0 ? allocated : logical
            metrics.record(entries: 1, allocated: bytes, reclaimable: bytes)
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
