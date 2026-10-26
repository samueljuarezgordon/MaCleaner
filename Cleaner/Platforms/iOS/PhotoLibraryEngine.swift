#if os(iOS)
import os
import Photos

/// Motor de limpieza de iOS / iPadOS.
///
/// El sandbox de iOS no permite acceder al sistema de archivos general, así que el motor
/// trabaja exclusivamente sobre la Fototeca mediante PhotoKit y Vision.
nonisolated struct PhotoLibraryEngine: CleaningEngine {
    enum EngineError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            "MaCleaner necesita acceso a la fototeca. Puedes concederlo en Ajustes → Privacidad → Fotos."
        }
    }

    private static let logger = Logger(subsystem: "MaCleaner", category: "Fotos")

    /// Vídeos a partir de este tamaño se proponen como "grandes".
    static let largeVideoThreshold: Int64 = 200 * 1024 * 1024

    private let detector = VisualDuplicateDetector()

    var supportedCategories: [CleaningCategory] {
        [.duplicatePhotos, .duplicateVideos, .largeVideos, .screenshots, .screenRecordings, .burstPhotos]
    }

    // MARK: - Escaneo

    @concurrent
    func scan(
        categories: Set<CleaningCategory>,
        progress: AsyncStream<ScanProgress>.Continuation
    ) async throws -> ScanSummary {
        try await scan(categories: categories, progress: progress, metrics: ScanMetrics())
    }

    /// `metrics` se comparte con el resto del análisis para que el contador sea uno solo.
    @concurrent
    func scan(
        categories: Set<CleaningCategory>,
        progress: AsyncStream<ScanProgress>.Continuation,
        metrics: ScanMetrics
    ) async throws -> ScanSummary {
        let wanted = categories.intersection(supportedCategories)
        let clock = ContinuousClock()
        let start = clock.now
        guard !wanted.isEmpty else {
            return ScanSummary(items: [], entriesVisited: 0, duration: clock.now - start, inaccessibleCategories: [])
        }

        // `.readWrite` porque borrar requiere acceso de escritura.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw EngineError.accessDenied }

        // Todas las categorías elegidas se marcan en curso desde el principio: antes se quedaban
        // «pendientes» mientras se leían los tamaños de toda la fototeca y parecía colgado.
        for category in supportedCategories where wanted.contains(category) {
            progress.yield(.started(category))
        }

        let report: @Sendable (Int) -> Void = { _ in
            let snapshot = metrics.snapshot
            progress.yield(.metrics(entriesVisited: snapshot.entriesVisited, bytes: snapshot.allocatedBytes))
        }
        var items: [ScanItem] = []

        // Primero lo rápido (vídeos, capturas, ráfagas), para que termine aunque la búsqueda de
        // duplicados tarde. Los tamaños solo se leen de lo que se va a proponer: leerlos de toda
        // la fototeca era lo más lento del análisis.
        let videos = wanted.isDisjoint(with: [.largeVideos, .screenRecordings, .duplicateVideos]) ? [] : Self.fetchAssets(of: .video)
        var videoInfos: [String: AssetInfo] = [:]

        if !wanted.isDisjoint(with: [.largeVideos, .screenRecordings]) {
            videoInfos = await AssetSizeResolver.infos(for: videos, metrics: metrics, onProgress: report)
            try Task.checkCancellation()

            if wanted.contains(.largeVideos) {
                items += videoInfos.values
                    .filter { $0.allocatedBytes >= Self.largeVideoThreshold }
                    .map { Self.item(from: $0, category: .largeVideos) }
                progress.yield(.finished(.largeVideos, bytes: Self.bytes(of: .largeVideos, in: items)))
            }
            if wanted.contains(.screenRecordings) {
                for video in videos where video.asset.mediaSubtypes.contains(.videoScreenRecording) {
                    guard let info = videoInfos[video.localIdentifier] else { continue }
                    items.append(Self.item(from: info, category: .screenRecordings))
                }
                progress.yield(.finished(.screenRecordings, bytes: Self.bytes(of: .screenRecordings, in: items)))
            }
        }

        let images = wanted.isDisjoint(with: [.duplicatePhotos, .screenshots, .burstPhotos]) ? [] : Self.fetchAssets(of: .image)

        if wanted.contains(.screenshots) {
            let screenshots = images.filter { $0.asset.mediaSubtypes.contains(.photoScreenshot) }
            let infos = await AssetSizeResolver.infos(for: screenshots, metrics: metrics, onProgress: report)
            try Task.checkCancellation()
            items += screenshots.compactMap { infos[$0.localIdentifier] }.map { Self.item(from: $0, category: .screenshots) }
            progress.yield(.finished(.screenshots, bytes: Self.bytes(of: .screenshots, in: items)))
        }

        // Ráfagas: la búsqueda normal solo devuelve la foto representativa de cada una.
        if wanted.contains(.burstPhotos) {
            let extras = Self.fetchBurstExtras(excluding: Set(images.map(\.localIdentifier)))
            let extraInfos = await AssetSizeResolver.infos(for: extras, metrics: metrics, onProgress: report)
            try Task.checkCancellation()
            items += extraInfos.values.map { Self.item(from: $0, category: .burstPhotos) }
            progress.yield(.finished(.burstPhotos, bytes: Self.bytes(of: .burstPhotos, in: items)))
        }

        // Duplicados (Vision): lo más costoso, con su propio porcentaje. Primero los vídeos,
        // que son menos.
        if wanted.contains(.duplicateVideos) {
            items += try await duplicates(among: videos, media: .videos, category: .duplicateVideos, knownInfos: videoInfos, metrics: metrics, progress: progress, report: report)
        }
        if wanted.contains(.duplicatePhotos) {
            items += try await duplicates(among: images, media: .photos, category: .duplicatePhotos, knownInfos: [:], metrics: metrics, progress: progress, report: report)
        }
        report(0)

        // Un elemento puede estar en dos categorías (un vídeo grande duplicado, una captura
        // repetida): gana la de duplicados, que explica mejor por qué se propone.
        let isDuplicate: (ScanItem) -> Bool = { $0.category == .duplicatePhotos || $0.category == .duplicateVideos }
        var seen: Set<String> = []
        items = (items.filter(isDuplicate) + items.filter { !isDuplicate($0) }).filter { seen.insert($0.id).inserted }

        return ScanSummary(
            items: items.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            entriesVisited: metrics.snapshot.entriesVisited,
            duration: clock.now - start,
            inaccessibleCategories: []
        )
    }

    /// Busca copias entre `assets` y propone borrar todas menos la más pesada de cada grupo.
    private func duplicates(
        among assets: [AssetReference],
        media: VisualDuplicateDetector.Media,
        category: CleaningCategory,
        knownInfos: [String: AssetInfo],
        metrics: ScanMetrics,
        progress: AsyncStream<ScanProgress>.Continuation,
        report: @escaping @Sendable (Int) -> Void
    ) async throws -> [ScanItem] {
        let total = assets.count
        let clock = ContinuousClock()
        let start = clock.now
        progress.yield(.fraction(category, done: 0, total: total))
        let cache = FeaturePrintCache(name: media == .videos ? "videos" : "fotos")
        let prints = await detector.featurePrints(for: assets, cache: cache) { done in
            progress.yield(.fraction(category, done: done, total: total))
        }
        metrics.record(entries: total, allocated: 0, reclaimable: 0)
        report(0)
        try Task.checkCancellation()
        let printed = clock.now

        let groups = await detector.duplicateGroups(in: prints, media: media)
        try Task.checkCancellation()
        Self.logger.info("\(category.rawValue, privacy: .public): \(prints.count) huellas de \(total) en \((printed - start).formatted(), privacy: .public), \(groups.count) grupos en \((clock.now - printed).formatted(), privacy: .public)")

        // Solo se leen los tamaños que faltan, y solo de lo que tiene alguna copia.
        let byID = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let missing = groups.flatMap { $0 }.filter { knownInfos[$0] == nil }.compactMap { byID[$0] }
        let resolved = await AssetSizeResolver.infos(for: missing, metrics: metrics, onProgress: report)
        let infos = knownInfos.merging(resolved, uniquingKeysWith: { known, _ in known })

        var items: [ScanItem] = []
        for group in groups {
            // Se conserva la copia más pesada (normalmente la de mayor calidad).
            let ranked = group.sorted { (infos[$0]?.allocatedBytes ?? 0) > (infos[$1]?.allocatedBytes ?? 0) }
            let keptName = ranked.first.flatMap { infos[$0]?.filename }
            for identifier in ranked.dropFirst() {
                guard let info = infos[identifier] else { continue }
                items.append(Self.item(from: info, category: category, keptCopy: keptName))
            }
        }
        progress.yield(.finished(category, bytes: items.reduce(0) { $0 + $1.reclaimableBytes }))
        return items
    }

    private static func bytes(of category: CleaningCategory, in items: [ScanItem]) -> Int64 {
        items.filter { $0.category == category }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    /// Fotos de ráfagas que no son la representativa ni una elegida por el usuario.
    private static func fetchBurstExtras(excluding visible: Set<String>) -> [AssetReference] {
        let options = PHFetchOptions()
        options.includeAllBurstAssets = true
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var references: [AssetReference] = []
        result.enumerateObjects { asset, _, _ in
            guard asset.representsBurst, !visible.contains(asset.localIdentifier),
                  !asset.burstSelectionTypes.contains(.userPick) else { return }
            references.append(AssetReference(asset: asset))
        }
        return references
    }

    private static func fetchAssets(of mediaType: PHAssetMediaType) -> [AssetReference] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        let result = PHAsset.fetchAssets(with: mediaType, options: options)

        var references: [AssetReference] = []
        references.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            references.append(AssetReference(asset: asset))
        }
        return references
    }

    /// Ninguna foto se considera «segura»: borrarla se sincroniza con iCloud y con tus otros
    /// dispositivos, así que como mínimo hay que revisarla. Además, nunca se marca sola
    /// (`RemovalMethod.needsExplicitChoice`).
    private static func item(from info: AssetInfo, category: CleaningCategory, keptCopy: String? = nil) -> ScanItem {
        let age = info.creationDate.map { " Es de \($0.formatted(.relative(presentation: .named)))." } ?? ""
        let kept = keptCopy.map { " Se conserva «\($0)»." } ?? " Se conserva la copia de mayor calidad."
        let sync = " Irá a «Eliminados recientemente» 30 días y, con Fotos en iCloud, se borrará también de tus otros dispositivos."
        let (risk, reason): (RiskLevel, String) = switch category {
        case .duplicatePhotos:
            (.moderate, "Copia visualmente idéntica de otra foto.\(kept)\(sync)")
        case .duplicateVideos:
            (.moderate, "Copia de otro vídeo: misma duración, proporción e imagen.\(kept)\(sync)")
        case .screenshots:
            (.moderate, "Captura de pantalla.\(age) Revísala por si contiene algo que quieras conservar.\(sync)")
        case .screenRecordings:
            (.moderate, "Grabación de pantalla.\(age)\(sync)")
        case .burstPhotos:
            (.moderate, "Foto de una ráfaga que no elegiste como favorita. La foto principal de la ráfaga se conserva.\(sync)")
        default:
            (.high, "Vídeo personal.\(age) Asegúrate de tener otra copia antes de borrarlo.\(sync)")
        }
        return ScanItem(
            id: info.localIdentifier,
            displayName: info.filename,
            location: "Fototeca",
            category: category,
            allocatedBytes: info.allocatedBytes,
            reclaimableBytes: info.allocatedBytes,
            lastModified: info.creationDate,
            risk: risk,
            reason: reason,
            removal: .photoLibrary
        )
    }

    // MARK: - Limpieza

    /// Borra los assets. iOS muestra su propia confirmación al usuario y los mueve a
    /// "Eliminados recientemente", así que el espacio se libera del todo al vaciar esa
    /// carpeta o pasados 30 días.
    @concurrent
    func clean(_ items: [ScanItem]) async throws -> CleaningReport {
        let identifiers = items.map(\.id)
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
        // Los assets quedan en "Eliminados recientemente", el equivalente a la Papelera.
        return CleaningReport(
            reclaimedBytes: 0,
            trashedBytes: items.reduce(0) { $0 + $1.reclaimableBytes },
            failures: [],
            photosMovedToRecentlyDeleted: items.count
        )
    }
}
#endif
