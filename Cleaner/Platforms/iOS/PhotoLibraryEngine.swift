#if os(iOS)
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

    /// Vídeos a partir de este tamaño se proponen como "grandes".
    static let largeVideoThreshold: Int64 = 200 * 1024 * 1024

    private let detector = VisualDuplicateDetector()

    var supportedCategories: [CleaningCategory] {
        [.duplicatePhotos, .largeVideos, .screenshots, .screenRecordings, .burstPhotos]
    }

    // MARK: - Escaneo

    @concurrent
    func scan(progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary {
        // `.readWrite` porque borrar requiere acceso de escritura.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw EngineError.accessDenied }

        let clock = ContinuousClock()
        let start = clock.now
        let metrics = ScanMetrics()
        var items: [ScanItem] = []

        // Fotos duplicadas
        progress.yield(.started(.duplicatePhotos))
        let images = Self.fetchAssets(of: .image)
        let imageInfos = await AssetSizeResolver.infos(for: images, metrics: metrics)
        try Task.checkCancellation()
        reportProgress(metrics, to: progress)

        let prints = await detector.featurePrints(for: images)
        try Task.checkCancellation()
        let groups = await detector.duplicateGroups(in: prints)

        for group in groups {
            // Se conserva la copia más pesada (normalmente la de mayor calidad); el resto se
            // propone para borrar.
            let ranked = group.sorted {
                (imageInfos[$0]?.allocatedBytes ?? 0) > (imageInfos[$1]?.allocatedBytes ?? 0)
            }
            for identifier in ranked.dropFirst() {
                guard let info = imageInfos[identifier] else { continue }
                items.append(Self.item(from: info, category: .duplicatePhotos))
            }
        }

        // Vídeos grandes
        try Task.checkCancellation()
        progress.yield(.finished(.duplicatePhotos, bytes: items.reduce(0) { $0 + $1.reclaimableBytes }))
        progress.yield(.started(.largeVideos))
        let videos = Self.fetchAssets(of: .video)
        let videoInfos = await AssetSizeResolver.infos(for: videos, metrics: metrics)
        reportProgress(metrics, to: progress)

        items += videoInfos.values
            .filter { $0.allocatedBytes >= Self.largeVideoThreshold }
            .map { Self.item(from: $0, category: .largeVideos) }

        progress.yield(.finished(.largeVideos, bytes: items.filter { $0.category == .largeVideos }.reduce(0) { $0 + $1.reclaimableBytes }))

        // Capturas y grabaciones de pantalla (reutilizan los tamaños ya calculados).
        try Task.checkCancellation()
        progress.yield(.started(.screenshots))
        for image in images where image.asset.mediaSubtypes.contains(.photoScreenshot) {
            guard let info = imageInfos[image.localIdentifier] else { continue }
            items.append(Self.item(from: info, category: .screenshots))
        }
        progress.yield(.finished(.screenshots, bytes: Self.bytes(of: .screenshots, in: items)))

        progress.yield(.started(.screenRecordings))
        for video in videos where video.asset.mediaSubtypes.contains(.videoScreenRecording) {
            guard let info = videoInfos[video.localIdentifier] else { continue }
            items.append(Self.item(from: info, category: .screenRecordings))
        }
        progress.yield(.finished(.screenRecordings, bytes: Self.bytes(of: .screenRecordings, in: items)))

        // Ráfagas: la búsqueda normal solo devuelve la foto representativa de cada una.
        try Task.checkCancellation()
        progress.yield(.started(.burstPhotos))
        let visible = Set(images.map(\.localIdentifier))
        let extras = Self.fetchBurstExtras(excluding: visible)
        let extraInfos = await AssetSizeResolver.infos(for: extras, metrics: metrics)
        items += extraInfos.values.map { Self.item(from: $0, category: .burstPhotos) }
        progress.yield(.finished(.burstPhotos, bytes: Self.bytes(of: .burstPhotos, in: items)))
        reportProgress(metrics, to: progress)

        // Una foto puede ser a la vez duplicada y captura: gana la primera categoría.
        var seen: Set<String> = []
        items = items.filter { seen.insert($0.id).inserted }

        return ScanSummary(
            items: items.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            entriesVisited: metrics.snapshot.entriesVisited,
            duration: clock.now - start,
            inaccessibleCategories: []
        )
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

    private static func item(from info: AssetInfo, category: CleaningCategory) -> ScanItem {
        let age = info.creationDate.map { " Es de \($0.formatted(.relative(presentation: .named)))." } ?? ""
        let isOld = info.creationDate.map { $0.timeIntervalSinceNow < -90 * 86_400 } ?? false
        let (risk, reason): (RiskLevel, String) = switch category {
        case .duplicatePhotos:
            (.safe, "Copia visualmente idéntica de otra foto. Se conserva la de mayor calidad y esta va a «Eliminados recientemente» durante 30 días.")
        case .screenshots:
            isOld
                ? (.safe, "Captura antigua.\(age) Si la guardaste por algo concreto, probablemente ya no la necesites.")
                : (.moderate, "Captura reciente.\(age) Revísala por si contiene algo que quieras conservar.")
        case .screenRecordings:
            (.moderate, "Grabación de pantalla.\(age) Irá a «Eliminados recientemente» durante 30 días.")
        case .burstPhotos:
            (.safe, "Foto de una ráfaga que no elegiste como favorita. La foto principal de la ráfaga se conserva.")
        default:
            (.high, "Vídeo personal. Asegúrate de tener una copia antes de borrarlo; irá a «Eliminados recientemente» durante 30 días.")
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

    private func reportProgress(_ metrics: ScanMetrics, to progress: AsyncStream<ScanProgress>.Continuation) {
        let snapshot = metrics.snapshot
        progress.yield(.metrics(entriesVisited: snapshot.entriesVisited, bytes: snapshot.allocatedBytes))
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
            failures: []
        )
    }
}
#endif
