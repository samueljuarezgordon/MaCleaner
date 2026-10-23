#if os(iOS)
import Photos

/// Envoltorio `Sendable` de `PHAsset` para pasarlo a tareas hijas.
///
/// `PHAsset` es un objeto de modelo inmutable: Photos nunca lo modifica después de
/// devolverlo en un `PHFetchResult` (los cambios producen objetos nuevos). Por eso es
/// seguro leerlo desde varios hilos, aunque el SDK no lo marque como `Sendable`.
nonisolated struct AssetReference: @unchecked Sendable {
    let asset: PHAsset

    var localIdentifier: String { asset.localIdentifier }
}

/// Información de tamaño de un asset.
nonisolated struct AssetInfo: Sendable {
    let localIdentifier: String
    let filename: String
    let allocatedBytes: Int64
    let creationDate: Date?
}

nonisolated enum AssetSizeResolver {
    private static let fileSizeKey = "fileSize"

    /// Tamaño real en bytes de todos los recursos del asset: original, versiones editadas,
    /// vídeo emparejado de una Live Photo, etc.
    ///
    /// - Important: `fileSize` no es una propiedad pública de `PHAssetResource`, así que
    ///   se lee por KVC. Antes se comprueba con `responds(to:)`: si Apple la eliminara, una
    ///   clave inexistente lanzaría `NSUndefinedKeyException` y la app se cerraría.
    static func info(for reference: AssetReference) -> AssetInfo {
        let resources = PHAssetResource.assetResources(for: reference.asset)
        var total: Int64 = 0

        for resource in resources where resource.responds(to: NSSelectorFromString(fileSizeKey)) {
            if let size = resource.value(forKey: fileSizeKey) as? Int64 {
                total += size
            }
        }

        return AssetInfo(
            localIdentifier: reference.localIdentifier,
            filename: resources.first?.filename ?? reference.localIdentifier,
            allocatedBytes: total,
            creationDate: reference.asset.creationDate
        )
    }

    /// Resuelve los tamaños en paralelo con una ventana deslizante de tareas.
    @concurrent
    static func infos(
        for references: [AssetReference],
        metrics: ScanMetrics,
        maxConcurrency: Int = ProcessInfo.processInfo.activeProcessorCount
    ) async -> [String: AssetInfo] {
        await withTaskGroup(of: AssetInfo.self) { group in
            var pending = references.makeIterator()
            for _ in 0..<max(1, maxConcurrency) {
                guard let reference = pending.next() else { break }
                group.addTask { info(for: reference) }
            }

            var result: [String: AssetInfo] = [:]
            result.reserveCapacity(references.count)
            while let info = await group.next() {
                result[info.localIdentifier] = info
                metrics.record(entries: 1, allocated: info.allocatedBytes, reclaimable: 0)
                if !Task.isCancelled, let reference = pending.next() {
                    group.addTask { Self.info(for: reference) }
                }
            }
            return result
        }
    }
}
#endif
