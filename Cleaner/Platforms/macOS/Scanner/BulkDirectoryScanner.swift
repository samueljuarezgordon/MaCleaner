#if os(macOS)
import Darwin
import Foundation

/// Entrada de directorio decodificada de un lote de `getattrlistbulk`.
nonisolated struct DirectoryEntry: Sendable {
    let name: String
    let isDirectory: Bool
    /// Equivalente en el kernel de `URLResourceKey.totalFileAllocatedSizeKey`: bloques
    /// realmente asignados de todos los forks. En archivos dispersos (sparse) es menor que
    /// el tamaño lógico.
    let allocatedBytes: Int64
    /// `ATTR_CMNEXT_PRIVATESIZE`: bytes que no se comparten con ningún clon APFS, es decir,
    /// lo que de verdad se libera al borrar el archivo.
    let reclaimableBytes: Int64
    let modificationDate: Date
}

/// Archivo encontrado durante un recorrido que supera `TraversalOptions.largeFileThreshold`.
nonisolated struct FoundFile: Sendable {
    let path: String
    let name: String
    let allocatedBytes: Int64
    let reclaimableBytes: Int64
    let modificationDate: Date
}

/// Qué hacer con un subdirectorio durante un recorrido.
nonisolated enum DirectoryDecision: Sendable {
    /// Recorrerlo con normalidad.
    case descend
    /// Ignorarlo por completo.
    case skip
    /// No recorrerlo, pero devolver su ruta en `TreeUsage.collectedDirectories`.
    case collect
}

nonisolated struct TraversalOptions: Sendable {
    /// Profundidad máxima. Los hijos inmediatos de la raíz tienen profundidad 1.
    var maxDepth: Int?
    /// Si se indica, los archivos de este tamaño o mayores se devuelven en `largeFiles`.
    var largeFileThreshold: Int64?
    /// Decide para cada subdirectorio (nombre, ruta completa) si se recorre.
    var classifyDirectory: (@Sendable (_ name: String, _ path: String) -> DirectoryDecision)?

    init(
        maxDepth: Int? = nil,
        largeFileThreshold: Int64? = nil,
        classifyDirectory: (@Sendable (_ name: String, _ path: String) -> DirectoryDecision)? = nil
    ) {
        self.maxDepth = maxDepth
        self.largeFileThreshold = largeFileThreshold
        self.classifyDirectory = classifyDirectory
    }
}

/// Resultado agregado de un recorrido.
nonisolated struct TreeUsage: Sendable {
    var entries = 0
    var allocatedBytes: Int64 = 0
    var reclaimableBytes: Int64 = 0
    /// Fecha de modificación más reciente de cualquier archivo del árbol.
    var lastModified: Date?
    var largeFiles: [FoundFile] = []
    var collectedDirectories: [String] = []
}

nonisolated enum BulkScanError: Error {
    case openFailed(path: String, code: Int32)
    case readFailed(path: String, code: Int32)

    /// La carpeta existe pero TCC (Acceso total al disco) o los permisos impiden leerla.
    var isPermissionDenied: Bool {
        switch self {
        case .openFailed(_, let code), .readFailed(_, let code): code == EPERM || code == EACCES
        }
    }
}

/// Escáner de disco de alto rendimiento basado en `getattrlistbulk(2)`.
///
/// Cada llamada al kernel llena un búfer de 64 KB con decenas o cientos de entradas
/// (nombre, tipo, fecha y tamaños), en vez de hacer un `stat` por archivo como
/// `FileManager.enumerator`.
nonisolated struct BulkDirectoryScanner: Sendable {
    static let bufferSize = 64 * 1024

    /// Número máximo de directorios que se leen en paralelo.
    let maxConcurrentDirectories: Int

    init(maxConcurrentDirectories: Int = ProcessInfo.processInfo.activeProcessorCount * 2) {
        self.maxConcurrentDirectories = max(1, maxConcurrentDirectories)
    }

    // MARK: - API pública

    /// Devuelve las entradas inmediatas de `path`.
    func entries(in path: String) throws(BulkScanError) -> [DirectoryEntry] {
        var result: [DirectoryEntry] = []
        try Self.readEntries(atPath: path) { result.append($0) }
        return result
    }

    /// Recorre un árbol completo. Avanza por niveles (BFS) y lee cada nivel en paralelo con
    /// un `TaskGroup` limitado a `maxConcurrentDirectories` tareas simultáneas.
    @concurrent
    func measureTree(
        at root: String,
        metrics: ScanMetrics,
        options: TraversalOptions = TraversalOptions()
    ) async throws -> TreeUsage {
        var usage = TreeUsage()
        var frontier = [root]
        var depth = 0

        while !frontier.isEmpty {
            try Task.checkCancellation()
            depth += 1
            let allowsDescending = options.maxDepth.map { depth < $0 } ?? true
            var nextFrontier: [String] = []

            await withTaskGroup(of: DirectoryListing.self) { group in
                var pending = frontier.makeIterator()

                // Se arranca con N tareas y se añade otra cada vez que termina una
                // (ventana deslizante), para no crear miles de tareas de golpe.
                for _ in 0..<maxConcurrentDirectories {
                    guard let directory = pending.next() else { break }
                    group.addTask { Self.list(directory, metrics: metrics, options: options) }
                }

                while let listing = await group.next() {
                    usage.entries += listing.entries
                    usage.allocatedBytes += listing.allocatedBytes
                    usage.reclaimableBytes += listing.reclaimableBytes
                    usage.largeFiles += listing.largeFiles
                    usage.collectedDirectories += listing.collectedDirectories
                    if let date = listing.lastModified, date > (usage.lastModified ?? .distantPast) {
                        usage.lastModified = date
                    }
                    if allowsDescending {
                        nextFrontier += listing.subdirectories
                    }

                    if !Task.isCancelled, let directory = pending.next() {
                        group.addTask { Self.list(directory, metrics: metrics, options: options) }
                    }
                }
            }
            frontier = nextFrontier
        }
        return usage
    }

    // MARK: - Implementación

    private struct DirectoryListing: Sendable {
        var subdirectories: [String] = []
        var collectedDirectories: [String] = []
        var largeFiles: [FoundFile] = []
        var entries = 0
        var allocatedBytes: Int64 = 0
        var reclaimableBytes: Int64 = 0
        var lastModified: Date?
    }

    /// Lee un único directorio. Los directorios ilegibles (EACCES, EPERM por TCC…) se
    /// ignoran para que no aborten el recorrido completo.
    private static func list(
        _ directory: String,
        metrics: ScanMetrics,
        options: TraversalOptions
    ) -> DirectoryListing {
        var listing = DirectoryListing()
        guard !Task.isCancelled else { return listing }

        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        do {
            try readEntries(atPath: directory) { entry in
                listing.entries += 1
                let path = prefix + entry.name

                if entry.isDirectory {
                    switch options.classifyDirectory?(entry.name, path) ?? .descend {
                    case .descend: listing.subdirectories.append(path)
                    case .collect: listing.collectedDirectories.append(path)
                    case .skip: break
                    }
                    return
                }

                listing.allocatedBytes += entry.allocatedBytes
                listing.reclaimableBytes += entry.reclaimableBytes
                if entry.modificationDate > (listing.lastModified ?? .distantPast) {
                    listing.lastModified = entry.modificationDate
                }
                if let threshold = options.largeFileThreshold, entry.allocatedBytes >= threshold {
                    listing.largeFiles.append(FoundFile(
                        path: path,
                        name: entry.name,
                        allocatedBytes: entry.allocatedBytes,
                        reclaimableBytes: entry.reclaimableBytes,
                        modificationDate: entry.modificationDate
                    ))
                }
            }
        } catch {
            return listing
        }

        metrics.record(
            entries: listing.entries,
            allocated: listing.allocatedBytes,
            reclaimable: listing.reclaimableBytes
        )
        return listing
    }

    /// Atributos solicitados. Con `FSOPT_PACK_INVAL_ATTRS` todos se empaquetan siempre en
    /// este orden fijo (common por orden de bit → file → fork/extended), aunque no sean
    /// válidos para la entrada:
    ///
    ///     u_int32_t        length
    ///     attribute_set_t  returned           (ATTR_CMN_RETURNED_ATTRS)
    ///     u_int32_t        error              (ATTR_CMN_ERROR)
    ///     attrreference_t  name               (ATTR_CMN_NAME)
    ///     fsobj_type_t     objType            (ATTR_CMN_OBJTYPE)
    ///     timespec         modificationTime   (ATTR_CMN_MODTIME)
    ///     off_t            allocSize          (ATTR_FILE_ALLOCSIZE)
    ///     off_t            privateSize        (ATTR_CMNEXT_PRIVATESIZE)
    private static func makeAttributeList() -> attrlist {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = ATTR_CMN_RETURNED_ATTRS
            | attrgroup_t(ATTR_CMN_NAME)
            | attrgroup_t(ATTR_CMN_ERROR)
            | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_MODTIME)
        list.fileattr = attrgroup_t(ATTR_FILE_ALLOCSIZE)
        list.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        return list
    }

    private static let options = UInt64(FSOPT_PACK_INVAL_ATTRS) | UInt64(FSOPT_ATTR_CMN_EXTENDED)

    private static func readEntries(
        atPath path: String,
        _ body: (DirectoryEntry) -> Void
    ) throws(BulkScanError) {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw .openFailed(path: path, code: errno) }
        defer { close(descriptor) }

        var attributes = makeAttributeList()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        while true {
            let count = getattrlistbulk(descriptor, &attributes, buffer.baseAddress, bufferSize, options)
            if count == 0 { return }
            if count < 0 {
                if errno == EINTR { continue }
                throw .readFailed(path: path, code: errno)
            }
            // Cada lote se procesa dentro de su propio pool para que los objetos temporales
            // de Foundation (bridging de String, etc.) se liberen antes del siguiente lote.
            autoreleasepool {
                parseBatch(UnsafeRawBufferPointer(buffer), count: Int(count), body)
            }
        }
    }

    private static func parseBatch(
        _ buffer: UnsafeRawBufferPointer,
        count: Int,
        _ body: (DirectoryEntry) -> Void
    ) {
        guard let base = buffer.baseAddress else { return }
        var entryStart = base

        for _ in 0..<count {
            // Los atributos están alineados a 4 bytes; los `off_t` y `timespec` pueden no
            // estar alineados a 8, de ahí `loadUnaligned`.
            let length = Int(entryStart.loadUnaligned(as: UInt32.self))
            var field = entryStart + MemoryLayout<UInt32>.size
            defer { entryStart += length }

            let returned = field.loadUnaligned(as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size

            let error = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size

            let nameReferenceStart = field
            let nameReference = field.loadUnaligned(as: attrreference_t.self)
            field += MemoryLayout<attrreference_t>.size

            let objectType = field.loadUnaligned(as: fsobj_type_t.self)
            field += MemoryLayout<fsobj_type_t>.size

            let modificationTime = field.loadUnaligned(as: timespec.self)
            field += MemoryLayout<timespec>.size

            let allocatedSize = field.loadUnaligned(as: off_t.self)
            field += MemoryLayout<off_t>.size

            let privateSize = field.loadUnaligned(as: off_t.self)

            guard error == 0 else { continue }

            // El offset de un attrreference_t es relativo al propio attrreference_t.
            let namePointer = (nameReferenceStart + Int(nameReference.attr_dataoffset))
                .assumingMemoryBound(to: CChar.self)
            let name = String(cString: namePointer)

            let isDirectory = objectType == fsobj_type_t(VDIR.rawValue)
            let isRegularFile = objectType == fsobj_type_t(VREG.rawValue)
            // Los enlaces simbólicos y otros nodos especiales no ocupan espacio de datos.
            let allocated: Int64 = isRegularFile ? Int64(allocatedSize) : 0
            let hasPrivateSize = returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0
            let reclaimable: Int64 = isRegularFile ? (hasPrivateSize ? Int64(privateSize) : allocated) : 0
            let modificationDate = Date(
                timeIntervalSince1970: TimeInterval(modificationTime.tv_sec)
                    + TimeInterval(modificationTime.tv_nsec) / 1_000_000_000
            )

            body(DirectoryEntry(
                name: name,
                isDirectory: isDirectory,
                allocatedBytes: allocated,
                reclaimableBytes: reclaimable,
                modificationDate: modificationDate
            ))
        }
    }
}
#endif
