#if os(iOS)
import Foundation
import Photos

/// Guarda las huellas de Vision entre análisis: el segundo análisis solo procesa las fotos y
/// vídeos nuevos o editados, que es lo que de verdad tardaba.
///
/// Vive en *Application Support* (no en Cachés, que la propia limpieza de MaCleaner vacía) y
/// se excluye de la copia de seguridad: se puede regenerar siempre.
nonisolated struct FeaturePrintCache: Sendable {
    /// Lo que se guarda de cada asset. El vector va en `Float16` para ocupar la mitad (unos
    /// 1,5 KB por foto); al leerlo se vuelve a normalizar.
    nonisolated private struct Entry: Codable {
        /// Fecha de modificación del asset: si cambia (por ejemplo, al editarlo), se recalcula.
        let stamp: Double
        let aspectRatio: Double
        let duration: Double
        let vector: Data
    }

    nonisolated private struct Archive: Codable {
        static let currentVersion = 1
        let version: Int
        let entries: [String: Entry]
    }

    let url: URL

    /// `name` distingue fotos y vídeos, que se analizan por separado.
    init(name: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        url = base.appending(path: "Huellas", directoryHint: .isDirectory).appending(path: "\(name)-v\(Archive.currentVersion).plist")
    }

    /// Marca que invalida la huella guardada cuando el asset cambia.
    static func stamp(for asset: PHAsset) -> Double {
        asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
    }

    /// Huellas guardadas, por `localIdentifier`. Vacío si no hay archivo o está dañado.
    func load() -> [String: FeaturePrint] {
        guard let data = try? Data(contentsOf: url),
              let archive = try? PropertyListDecoder().decode(Archive.self, from: data),
              archive.version == Archive.currentVersion else { return [:] }

        var prints: [String: FeaturePrint] = [:]
        prints.reserveCapacity(archive.entries.count)
        for (identifier, entry) in archive.entries {
            guard let vector = Self.vector(from: entry.vector) else { continue }
            prints[identifier] = FeaturePrint(
                localIdentifier: identifier,
                aspectRatio: entry.aspectRatio,
                duration: entry.duration,
                stamp: entry.stamp,
                vector: vector
            )
        }
        return prints
    }

    /// Sustituye lo guardado por `prints` (lo que ya no está en la fototeca desaparece).
    func save(_ prints: [FeaturePrint]) {
        var entries: [String: Entry] = [:]
        entries.reserveCapacity(prints.count)
        for print in prints {
            let halves = print.vector.map { Float16($0) }
            entries[print.localIdentifier] = Entry(
                stamp: print.stamp,
                aspectRatio: print.aspectRatio,
                duration: print.duration,
                vector: halves.withUnsafeBufferPointer { Data(buffer: $0) }
            )
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(Archive(version: Archive.currentVersion, entries: entries)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        var location = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? location.setResourceValues(values)
    }

    private static func vector(from data: Data) -> [Float]? {
        let count = data.count / MemoryLayout<Float16>.stride
        guard count > 0 else { return nil }
        let vector: [Float] = data.withUnsafeBytes { raw in
            raw.bindMemory(to: Float16.self).prefix(count).map { Float($0) }
        }
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        return vector.map { $0 / norm }
    }
}
#endif
