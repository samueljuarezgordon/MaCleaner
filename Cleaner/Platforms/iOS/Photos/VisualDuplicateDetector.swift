#if os(iOS)
import Photos
import UIKit
import Vision

/// Huella de características (Feature Print) de un asset.
///
/// `VNFeaturePrintObservation` no se modifica después de que Vision la genera; la
/// comparación con `computeDistance` es de solo lectura.
nonisolated struct FeaturePrint: @unchecked Sendable {
    let localIdentifier: String
    let observation: VNFeaturePrintObservation
}

/// Detección de duplicados visuales con Vision.
///
/// No usa hashes criptográficos (MD5/SHA): cualquier cambio de metadatos EXIF o una
/// recompresión JPEG cambian el hash por completo. Las huellas de Vision describen el
/// contenido de la imagen, así que dos copias visualmente idénticas tienen una distancia
/// euclidiana de 0 o muy cercana.
nonisolated struct VisualDuplicateDetector: Sendable {
    /// Distancia máxima para considerar dos imágenes duplicadas. Con la revisión 2 los
    /// vectores están normalizados y la distancia cae en [0, 2].
    ///
    /// Valores medidos con la revisión 2: misma imagen 0.0 · JPEG q=0.9 → 0.008 ·
    /// JPEG q=0.4 → 0.074 · reescalada al 25 % → 0.010 · recorte del 5 % → 0.24 ·
    /// fotos distintas pero muy parecidas → 0.25–0.43. Los recortes no se tratan como duplicados.
    var distanceThreshold: Float = 0.1

    /// Vision reescala internamente a una resolución baja, así que una miniatura basta y
    /// evita decodificar originales de 48 MP.
    var thumbnailSize = CGSize(width: 512, height: 512)

    var maxConcurrency = ProcessInfo.processInfo.activeProcessorCount

    // MARK: - Extracción de huellas

    @concurrent
    func featurePrints(for references: [AssetReference]) async -> [FeaturePrint] {
        let size = thumbnailSize
        return await withTaskGroup(of: FeaturePrint?.self) { group in
            var pending = references.makeIterator()
            for _ in 0..<max(1, maxConcurrency) {
                guard let reference = pending.next() else { break }
                group.addTask { await Self.featurePrint(for: reference, size: size) }
            }

            var prints: [FeaturePrint] = []
            prints.reserveCapacity(references.count)
            while let print = await group.next() {
                if let print { prints.append(print) }
                if !Task.isCancelled, let reference = pending.next() {
                    group.addTask { await Self.featurePrint(for: reference, size: size) }
                }
            }
            return prints
        }
    }

    private static func featurePrint(for reference: AssetReference, size: CGSize) async -> FeaturePrint? {
        guard let image = await thumbnail(for: reference, size: size) else { return nil }

        // Vision crea búferes intermedios autoliberados; se drenan en cada imagen para que la
        // memoria no crezca con cientos de fotos.
        return autoreleasepool {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            guard let observation = request.results?.first else { return nil }
            return FeaturePrint(localIdentifier: reference.localIdentifier, observation: observation)
        }
    }

    private static func thumbnail(for reference: AssetReference, size: CGSize) async -> CGImage? {
        let options = PHImageRequestOptions()
        // `.highQualityFormat` garantiza un único callback (sin versión degradada previa).
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        // No se descargan originales de iCloud solo para comparar.
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            PHImageManager.default().requestImage(
                for: reference.asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                once.resume(returning: image?.cgImage)
            }
        }
    }

    // MARK: - Agrupación

    /// Agrupa los assets visualmente idénticos y devuelve solo los grupos con dos o más
    /// elementos.
    ///
    /// La comparación por parejas es O(n²); las filas de la matriz se reparten entre tareas
    /// hijas y los pares resultantes se unen con un union-find.
    @concurrent
    func duplicateGroups(in prints: [FeaturePrint]) async -> [[String]] {
        let count = prints.count
        guard count > 1 else { return [] }

        let threshold = distanceThreshold
        let chunkSize = max(1, count / (max(1, maxConcurrency) * 4))

        let pairs: [(Int, Int)] = await withTaskGroup(of: [(Int, Int)].self) { group in
            for start in stride(from: 0, to: count, by: chunkSize) {
                let rows = start..<min(start + chunkSize, count)
                group.addTask {
                    var found: [(Int, Int)] = []
                    for i in rows {
                        if Task.isCancelled { break }
                        for j in (i + 1)..<count {
                            var distance: Float = 0
                            do {
                                try prints[i].observation.computeDistance(&distance, to: prints[j].observation)
                            } catch {
                                continue
                            }
                            if distance <= threshold {
                                found.append((i, j))
                            }
                        }
                    }
                    return found
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }

        var unionFind = UnionFind(count: count)
        for (i, j) in pairs {
            unionFind.union(i, j)
        }

        var groups: [Int: [String]] = [:]
        for index in 0..<count {
            groups[unionFind.find(index), default: []].append(prints[index].localIdentifier)
        }
        return groups.values.filter { $0.count > 1 }
    }
}

/// Union-find con compresión de caminos.
nonisolated private struct UnionFind {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func find(_ element: Int) -> Int {
        var root = element
        while parent[root] != root { root = parent[root] }
        var node = element
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        if rootA != rootB { parent[rootB] = rootA }
    }
}
#endif
