#if os(iOS)
import Accelerate
import Synchronization
import Photos
import UIKit
import Vision

/// Huella de características (Feature Print) de un asset, ya como vector normalizado.
///
/// Se guarda el vector y no la `VNFeaturePrintObservation`: así la comparación se hace con
/// productos de matrices (Accelerate) en lugar de millones de llamadas a `computeDistance`.
/// En los vídeos, la huella es la de su fotograma de portada.
nonisolated struct FeaturePrint: Sendable {
    let localIdentifier: String
    /// Ancho / alto en píxeles. Dos copias de la misma foto tienen la misma proporción.
    let aspectRatio: Double
    /// Duración en segundos (0 en fotos). Dos copias de un vídeo duran lo mismo.
    let duration: Double
    /// `FeaturePrintCache.stamp(for:)` del asset cuando se calculó la huella.
    let stamp: Double
    /// Vector de norma 1.
    let vector: [Float]
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

    /// Tiempo máximo por miniatura. Si para entonces Fotos solo ha entregado una versión de
    /// baja calidad, se usa esa; si no ha entregado nada, el asset se salta. Con 10 s y sin
    /// versión previa, cada vídeo guardado solo en iCloud costaba 10 s y el análisis no acababa.
    var thumbnailTimeout: Duration = .seconds(2)

    var maxConcurrency = ProcessInfo.processInfo.activeProcessorCount

    /// Qué se compara: cambia cómo se agrupan los candidatos antes de compararlos.
    nonisolated enum Media: Sendable {
        /// Por proporción, en tramos de 2 %.
        case photos
        /// Por duración, en tramos de 1 s. Además deben coincidir la proporción y la portada.
        case videos
    }

    /// Las proporciones se agrupan en tramos de este ancho (relativo, en escala logarítmica).
    /// Un tramo solo se compara consigo mismo y con el siguiente, en lugar de con todo.
    private static let aspectBucketWidth = 0.02
    /// Dos copias pueden diferir algo en proporción al reescalarse (redondeo de píxeles).
    private static let maximumAspectGap = 0.04
    /// Un vídeo recomprimido (por ejemplo, al enviarlo por WhatsApp) puede variar unas décimas.
    private static let maximumDurationGap = 1.0

    // MARK: - Extracción de huellas

    /// Calcula las huellas. `onProgress` recibe cuántas fotos van procesadas.
    ///
    /// Con `cache`, las huellas de los assets que no han cambiado se reutilizan y solo se calculan
    /// las nuevas. Lo calculado se guarda aunque el análisis se cancele: el siguiente sigue
    /// donde se quedó.
    @concurrent
    func featurePrints(
        for references: [AssetReference],
        cache: FeaturePrintCache? = nil,
        onProgress: @escaping @Sendable (Int) -> Void = { _ in }
    ) async -> [FeaturePrint] {
        let stored = cache?.load() ?? [:]
        var reused: [FeaturePrint] = []
        var missing: [AssetReference] = []
        for reference in references {
            if let print = stored[reference.localIdentifier], print.stamp == FeaturePrintCache.stamp(for: reference.asset) {
                reused.append(print)
            } else {
                missing.append(reference)
            }
        }
        let alreadyDone = reused.count
        onProgress(alreadyDone)

        let computed = await computePrints(for: missing) { done in onProgress(alreadyDone + done) }
        let prints = reused + computed
        cache?.save(prints)
        return prints
    }

    private func computePrints(
        for references: [AssetReference],
        onProgress: @escaping @Sendable (Int) -> Void
    ) async -> [FeaturePrint] {
        let size = thumbnailSize
        let timeout = thumbnailTimeout
        return await withTaskGroup(of: FeaturePrint?.self) { group in
            var pending = references.makeIterator()
            for _ in 0..<max(1, maxConcurrency) {
                guard let reference = pending.next() else { break }
                group.addTask { await Self.featurePrint(for: reference, size: size, timeout: timeout) }
            }

            var prints: [FeaturePrint] = []
            prints.reserveCapacity(references.count)
            var processed = 0
            while let print = await group.next() {
                if let print { prints.append(print) }
                processed += 1
                if processed.isMultiple(of: 25) { onProgress(processed) }
                if !Task.isCancelled, let reference = pending.next() {
                    group.addTask { await Self.featurePrint(for: reference, size: size, timeout: timeout) }
                }
            }
            onProgress(processed)
            return prints
        }
    }

    private static func featurePrint(for reference: AssetReference, size: CGSize, timeout: Duration) async -> FeaturePrint? {
        guard let image = await thumbnail(for: reference, size: size, timeout: timeout) else { return nil }

        // Vision crea búferes intermedios autoliberados; se drenan en cada imagen para que la
        // memoria no crezca con cientos de fotos.
        let vector: [Float]? = autoreleasepool {
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            request.imageCropAndScaleOption = .scaleFit

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            return request.results?.first.flatMap(Self.normalizedVector)
        }
        guard let vector else { return nil }

        let asset = reference.asset
        // Una proporción 0 rompería el logaritmo al agrupar.
        let ratio = asset.pixelWidth > 0 && asset.pixelHeight > 0 ? Double(asset.pixelWidth) / Double(asset.pixelHeight) : 1
        return FeaturePrint(
            localIdentifier: reference.localIdentifier,
            aspectRatio: ratio,
            duration: asset.duration,
            stamp: FeaturePrintCache.stamp(for: asset),
            vector: vector
        )
    }

    /// Copia el vector de la observación y lo deja con norma 1.
    private static func normalizedVector(of observation: VNFeaturePrintObservation) -> [Float]? {
        let count = observation.elementCount
        guard count > 0 else { return nil }
        var vector: [Float]
        switch observation.elementType {
        case .float:
            vector = observation.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
        case .double:
            vector = observation.data.withUnsafeBytes { $0.bindMemory(to: Double.self).prefix(count).map { Float($0) } }
        default:
            return nil
        }
        guard vector.count == count else { return nil }
        let norm = sqrt(vDSP.sumOfSquares(vector))
        guard norm > 0 else { return nil }
        vector = vDSP.divide(vector, norm)
        return vector
    }

    private static func thumbnail(for reference: AssetReference, size: CGSize, timeout: Duration) async -> CGImage? {
        let options = PHImageRequestOptions()
        // `.opportunistic`: Fotos entrega al momento la miniatura que ya tiene y, si puede, otra
        // mejor después. Así nunca se espera a ciegas a una versión que no está en el dispositivo.
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        // No se descargan originales de iCloud solo para comparar.
        options.isNetworkAccessAllowed = false

        let fallback = FallbackImage()
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            let requestID = PHImageManager.default().requestImage(
                for: reference.asset,
                targetSize: size,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded {
                    // Se guarda por si la buena no llega a tiempo.
                    fallback.store(image?.cgImage)
                } else {
                    once.resume(returning: image?.cgImage ?? fallback.image)
                }
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(returning: fallback.image)
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }

    // MARK: - Agrupación

    /// Agrupa los assets visualmente idénticos y devuelve solo los grupos con dos o más
    /// elementos.
    ///
    /// Antes se comparaba cada pareja con `computeDistance`: con 30 000 fotos eran 450 millones
    /// de llamadas y el análisis no terminaba nunca. Ahora:
    /// 1. Solo se comparan candidatos plausibles: fotos de proporción parecida, o vídeos de la
    ///    misma duración y proporción.
    /// 2. Con vectores de norma 1, `distancia² = 2 − 2·(a·b)`, así que basta un producto de
    ///    matrices por bloques (`vDSP_mmul`) y buscar los productos escalares altos.
    @concurrent
    func duplicateGroups(in prints: [FeaturePrint], media: Media = .photos) async -> [[String]] {
        let count = prints.count
        guard count > 1, let dimension = prints.first?.vector.count else { return [] }
        let usable = prints.indices.filter { prints[$0].vector.count == dimension }

        // distancia ≤ t  ⇔  a·b ≥ 1 − t²/2
        let minimumDot = 1 - distanceThreshold * distanceThreshold / 2

        var buckets: [Int: [Int]] = [:]
        for index in usable {
            let key = switch media {
            case .photos: Int((log(prints[index].aspectRatio) / Self.aspectBucketWidth).rounded(.down))
            case .videos: Int((prints[index].duration / Self.maximumDurationGap).rounded(.down))
            }
            buckets[key, default: []].append(index)
        }

        // Cada tramo se compara consigo mismo y con el tramo vecino de arriba.
        var jobs: [(rows: [Int], columns: [Int], sameBucket: Bool)] = []
        for (key, members) in buckets {
            if members.count > 1 { jobs.append((members, members, true)) }
            if let next = buckets[key + 1] { jobs.append((members, next, false)) }
        }

        let concurrency = max(1, maxConcurrency)
        let pairs: [(Int, Int)] = await withTaskGroup(of: [(Int, Int)].self) { group in
            var pendingJobs = jobs.makeIterator()
            for _ in 0..<concurrency {
                guard let job = pendingJobs.next() else { break }
                group.addTask { Self.similarPairs(rows: job.rows, columns: job.columns, sameBucket: job.sameBucket, prints: prints, dimension: dimension, minimumDot: minimumDot) }
            }
            var all: [(Int, Int)] = []
            while let found = await group.next() {
                all += found
                if !Task.isCancelled, let job = pendingJobs.next() {
                    group.addTask { Self.similarPairs(rows: job.rows, columns: job.columns, sameBucket: job.sameBucket, prints: prints, dimension: dimension, minimumDot: minimumDot) }
                }
            }
            return all
        }

        var unionFind = UnionFind(count: count)
        for (i, j) in pairs {
            unionFind.union(i, j)
        }

        var groups: [Int: [String]] = [:]
        for index in usable {
            groups[unionFind.find(index), default: []].append(prints[index].localIdentifier)
        }
        return groups.values.filter { $0.count > 1 }
    }

    /// Parejas (`rows[i]`, `columns[j]`) cuyo producto escalar supera `minimumDot`, calculado
    /// por bloques para que la matriz intermedia no pase de unos pocos MB.
    private static func similarPairs(
        rows: [Int],
        columns: [Int],
        sameBucket: Bool,
        prints: [FeaturePrint],
        dimension: Int,
        minimumDot: Float
    ) -> [(Int, Int)] {
        let rowBlock = 256
        let columnBlock = 2048
        var found: [(Int, Int)] = []

        for columnStart in stride(from: 0, to: columns.count, by: columnBlock) {
            if Task.isCancelled { break }
            let columnSlice = columns[columnStart..<min(columnStart + columnBlock, columns.count)]
            let n = columnSlice.count
            // B traspuesta (dimensión × n): columna j = vector de la foto j.
            var transposed = [Float](repeating: 0, count: dimension * n)
            for (j, index) in columnSlice.enumerated() {
                let vector = prints[index].vector
                for k in 0..<dimension { transposed[k * n + j] = vector[k] }
            }

            for rowStart in stride(from: 0, to: rows.count, by: rowBlock) {
                let rowSlice = rows[rowStart..<min(rowStart + rowBlock, rows.count)]
                // En el mismo tramo solo hace falta la mitad superior de la matriz.
                if sameBucket, rowStart >= columnStart + n { continue }
                let m = rowSlice.count
                var left = [Float]()
                left.reserveCapacity(m * dimension)
                for index in rowSlice { left += prints[index].vector }

                var products = [Float](repeating: 0, count: m * n)
                vDSP_mmul(left, 1, transposed, 1, &products, 1, vDSP_Length(m), vDSP_Length(n), vDSP_Length(dimension))

                for i in 0..<m {
                    let rowPosition = rowStart + i
                    for j in 0..<n where products[i * n + j] >= minimumDot {
                        let columnPosition = columnStart + j
                        if sameBucket, columnPosition <= rowPosition { continue }
                        let a = rowSlice[rowSlice.startIndex + i]
                        let b = columnSlice[columnSlice.startIndex + j]
                        guard areCompatible(prints[a], prints[b]) else { continue }
                        found.append((a, b))
                    }
                }
            }
        }
        return found
    }

    /// Una copia conserva la proporción y la duración (en fotos, la duración es 0 en ambas).
    private static func areCompatible(_ a: FeaturePrint, _ b: FeaturePrint) -> Bool {
        abs(log(a.aspectRatio / b.aspectRatio)) <= maximumAspectGap
            && abs(a.duration - b.duration) <= maximumDurationGap
    }
}

/// Versión de baja calidad que Fotos entrega primero, por si la buena no llega a tiempo.
nonisolated private final class FallbackImage: Sendable {
    /// Por debajo de esto la huella de Vision deja de ser fiable.
    private static let minimumSide = 100
    private let state = Mutex<CGImage?>(nil)

    func store(_ image: CGImage?) {
        guard let image, min(image.width, image.height) >= Self.minimumSide else { return }
        state.withLock { $0 = image }
    }

    var image: CGImage? {
        state.withLock { $0 }
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
