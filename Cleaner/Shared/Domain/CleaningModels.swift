import Foundation

// MARK: - Riesgo

/// Riesgo de borrar un elemento, de menor a mayor.
nonisolated enum RiskLevel: Int, Sendable, CaseIterable, Comparable, Identifiable {
    /// Se regenera automáticamente; borrarlo no tiene consecuencias visibles.
    case safe
    /// Se puede recuperar o regenerar, pero con un coste (volver a descargar, reconfigurar…).
    case moderate
    /// Puede contener datos personales o irrecuperables. Requiere revisión manual.
    case high

    var id: Int { rawValue }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .safe: "Seguro"
        case .moderate: "Revisar"
        case .high: "Riesgo alto"
        }
    }

    var summary: LocalizedStringResource {
        switch self {
        case .safe: "Se regenera solo. Puedes borrarlo sin preocuparte."
        case .moderate: "Se puede recuperar, pero tendrás que volver a descargarlo o configurarlo."
        case .high: "Podría ser tu única copia. Revísalo antes de borrarlo."
        }
    }

    var systemImage: String {
        switch self {
        case .safe: "checkmark.shield.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .high: "xmark.octagon.fill"
        }
    }
}

// MARK: - Método de borrado

nonisolated enum RemovalMethod: Sendable, Hashable {
    /// Borrado definitivo desde la app.
    case delete
    /// Se mueve a la Papelera (recuperable). El espacio se libera al vaciarla.
    case moveToTrash
    /// Borrado definitivo a través del demonio privilegiado (macOS).
    case privileged
    /// Borrado con PhotoKit; va a "Eliminados recientemente" (iOS).
    case photoLibrary
    /// `simctl delete <udid>`: elimina el simulador y todo su contenido (macOS).
    case simulatorDevice(udid: String)
    /// `simctl runtime delete <id>`: elimina un runtime de simulador (macOS).
    case simulatorRuntime(identifier: String)
    /// Mueve la app y sus datos asociados a la Papelera (macOS).
    case uninstallApp(relatedPaths: [String])
    /// Detiene un agente de `~/Library/LaunchAgents` y mueve su plist a la Papelera (macOS).
    case launchAgent(label: String)
    /// Detiene un agente o demonio de `/Library` y borra su plist con el asistente (macOS).
    case systemLaunchItem(label: String)
    /// Borra la copia local de un archivo de iCloud Drive; el archivo sigue en iCloud.
    case evictFromDevice

    /// Qué hace la app con el elemento, en lenguaje llano.
    var summary: LocalizedStringResource {
        switch self {
        case .delete: "Se borra definitivamente."
        case .moveToTrash: "Va a la Papelera. Podrás recuperarlo hasta que la vacíes."
        case .privileged: "Se borra definitivamente con el asistente privilegiado."
        case .photoLibrary: "Va a «Eliminados recientemente» durante 30 días."
        case .simulatorDevice: "Xcode elimina el simulador con simctl."
        case .simulatorRuntime: "Xcode elimina el runtime con simctl."
        case .uninstallApp: "La app y sus datos van a la Papelera. Podrás recuperarlos hasta que la vacíes."
        case .launchAgent: "Se detiene ahora y su archivo de configuración va a la Papelera: no volverá a arrancar."
        case .systemLaunchItem: "Se detiene y se borra su archivo de configuración con el asistente privilegiado."
        case .evictFromDevice: "Se borra solo la copia de este dispositivo. El archivo sigue en iCloud Drive y se vuelve a descargar al abrirlo."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .moveToTrash, .photoLibrary, .uninstallApp, .launchAgent, .evictFromDevice: true
        case .delete, .privileged, .simulatorDevice, .simulatorRuntime, .systemLaunchItem: false
        }
    }
}

// MARK: - Categorías y módulos

nonisolated enum CleaningCategory: String, Sendable, CaseIterable, Identifiable {
    // Basura del sistema
    case userCaches
    case appCaches
    case systemCaches
    case userLogs
    case systemLogs
    case ownAppCache
    // Desarrollo
    case xcodeDerivedData
    case xcodeDeviceSupport
    case xcodeArchives
    case xcodeCaches
    case simulatorDevices
    case simulatorRuntimes
    case simulatorCaches
    case packageCaches
    case projectDependencies
    // Mail
    case mailAttachments
    // Descargas
    case installers
    case compressedArchives
    // Aplicaciones
    case unusedApps
    case largeApps
    // Inicio y rendimiento
    case launchAgents
    case systemLaunchItems
    // Restos de apps
    case appLeftovers
    // Archivos grandes
    case largeFiles
    case deviceBackups
    // Papelera
    case trash
    // iCloud Drive
    case iCloudDriveDownloads
    // iOS / iPadOS
    case duplicatePhotos
    case largeVideos
    case screenshots
    case screenRecordings
    case burstPhotos

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .userCaches: "Cachés de usuario"
        case .appCaches: "Cachés de apps"
        case .systemCaches: "Cachés del sistema"
        case .userLogs: "Registros de usuario"
        case .systemLogs: "Registros del sistema"
        case .ownAppCache: "Caché de MaCleaner"
        case .xcodeDerivedData: "DerivedData de Xcode"
        case .xcodeDeviceSupport: "Soporte de dispositivos"
        case .xcodeArchives: "Archivos de Xcode"
        case .xcodeCaches: "Otros datos de Xcode"
        case .simulatorDevices: "Simuladores"
        case .simulatorRuntimes: "Runtimes de simulador"
        case .simulatorCaches: "Cachés de simuladores"
        case .packageCaches: "Cachés de paquetes"
        case .projectDependencies: "Dependencias y compilaciones"
        case .mailAttachments: "Adjuntos de Mail"
        case .installers: "Instaladores"
        case .compressedArchives: "Archivos comprimidos"
        case .unusedApps: "Apps poco usadas"
        case .largeApps: "Apps que ocupan mucho"
        case .launchAgents: "Agentes de tu usuario"
        case .systemLaunchItems: "Servicios de terceros"
        case .appLeftovers: "Restos de apps desinstaladas"
        case .largeFiles: "Archivos grandes"
        case .deviceBackups: "Copias de iPhone y iPad"
        case .trash: "Papelera"
        case .iCloudDriveDownloads: "Copias locales de iCloud Drive"
        case .duplicatePhotos: "Fotos duplicadas"
        case .largeVideos: "Vídeos grandes"
        case .screenshots: "Capturas de pantalla"
        case .screenRecordings: "Grabaciones de pantalla"
        case .burstPhotos: "Fotos de ráfagas"
        }
    }

    /// Qué es esta categoría, en lenguaje llano.
    var explanation: LocalizedStringResource {
        switch self {
        case .userCaches:
            "Archivos temporales que las apps guardan para ir más rápido. Se vuelven a crear cuando hacen falta."
        case .appCaches:
            "Cachés de navegador, GPU y código de apps basadas en Chromium o Electron (VS Code, Slack, Discord, Claude…). Se regeneran al abrir la app."
        case .systemCaches:
            "Cachés compartidas de macOS y de servicios del sistema. Requieren el asistente privilegiado."
        case .userLogs, .systemLogs:
            "Registros de actividad y de fallos. Solo sirven para diagnosticar problemas antiguos."
        case .ownAppCache:
            "Archivos temporales y cachés que la propia MaCleaner ha creado (miniaturas, restos de análisis)."
        case .xcodeDerivedData:
            "Productos intermedios de compilación de Xcode. La siguiente compilación tardará algo más."
        case .xcodeDeviceSupport:
            "Símbolos copiados de cada iPhone o iPad que conectaste a Xcode. Xcode los vuelve a copiar al conectar el dispositivo."
        case .xcodeArchives:
            "Builds archivadas para distribuir. Contienen los dSYM necesarios para interpretar informes de fallos."
        case .xcodeCaches:
            "Índices de documentación, productos de compilación sueltos y datos de Interface Builder que Xcode guarda para ir más rápido."
        case .simulatorDevices:
            "Cada simulador es un iPhone, iPad, Apple Watch o Apple TV virtual con sus propias apps instaladas, ajustes y datos de prueba."
        case .simulatorRuntimes:
            "Sistemas operativos (iOS 18, watchOS 11…) que Xcode descargó para que los simuladores puedan arrancar. Cada uno ocupa varios GB."
        case .simulatorCaches:
            "Cachés de los simuladores de iOS y de las vistas previas de SwiftUI."
        case .packageCaches:
            "Paquetes descargados por npm, pnpm, Gradle, Cargo, Go, Maven… Se vuelven a descargar si un proyecto los necesita."
        case .projectDependencies:
            "Dependencias descargadas (node_modules, Pods, entornos virtuales de Python) y resultados de compilación (.build, target, .next…) dentro de tus proyectos."
        case .mailAttachments:
            "Copias de los adjuntos que abriste desde Mail. El original sigue dentro del mensaje."
        case .installers:
            "Imágenes de disco (.dmg), paquetes (.pkg) e instaladores que ya no necesitas tras instalar la app."
        case .compressedArchives:
            "Archivos .zip, .rar, .7z… de tu carpeta Descargas."
        case .unusedApps:
            "Apps que no abres desde hace más de 3 meses. Se desinstalan junto con sus cachés, preferencias y datos."
        case .largeApps:
            "Apps de más de 1 GB, contando sus datos. Úsalo para decidir si te compensa tenerlas."
        case .launchAgents:
            "Programas que se abren solos al iniciar sesión (actualizadores, ayudantes de menú, sincronizadores…). Consumen memoria y batería aunque no los uses."
        case .systemLaunchItems:
            "Agentes y demonios de otras apps instalados para todos los usuarios en /Library. Arrancan con el Mac, incluso antes de iniciar sesión."
        case .appLeftovers:
            "Datos que dejaron apps que ya no están instaladas, o copias residuales de apps que se restablecieron."
        case .largeFiles:
            "Archivos personales de más de 500 MB. No es basura: decide tú si los necesitas."
        case .deviceBackups:
            "Copias de seguridad locales que hizo el Finder de tus iPhone y iPad."
        case .trash:
            "Elementos que ya enviaste a la Papelera."
        case .iCloudDriveDownloads:
            "Archivos de iCloud Drive descargados en este dispositivo. El original está en iCloud: puedes liberar la copia local sin perder nada."
        case .duplicatePhotos:
            "Fotos visualmente idénticas. Se conserva la copia de mayor calidad."
        case .largeVideos:
            "Vídeos de más de 200 MB."
        case .screenshots:
            "Capturas que hiciste para algo puntual (una dirección, un código, una conversación) y que se quedan ocupando espacio."
        case .screenRecordings:
            "Vídeos que grabaste de la pantalla. Suelen ser largos y pesados."
        case .burstPhotos:
            "Fotos de las ráfagas que no elegiste como favoritas. Solo se conserva la que ves en tu fototeca."
        }
    }

    /// Qué pasa si se borra, en lenguaje llano.
    var consequence: LocalizedStringResource {
        switch self {
        case .userCaches, .appCaches, .systemCaches:
            "Las apps pueden ir algo más lentas la primera vez que las abras mientras reconstruyen su caché."
        case .ownAppCache:
            "Ninguna: MaCleaner los vuelve a crear si los necesita."
        case .userLogs, .systemLogs:
            "Ninguna. Solo perderás el historial para diagnosticar fallos pasados."
        case .xcodeDerivedData:
            "La próxima compilación de cada proyecto empezará de cero y tardará más."
        case .xcodeDeviceSupport:
            "Al volver a conectar ese dispositivo, Xcode tardará unos minutos en preparar la depuración."
        case .xcodeArchives:
            "No podrás simbolizar informes de fallos ni volver a subir esas versiones."
        case .xcodeCaches:
            "Xcode reconstruirá los índices y la documentación cuando los necesite."
        case .simulatorDevices:
            "Pierdes las apps instaladas y los datos de prueba de ese simulador. Puedes crear uno nuevo en Xcode › Window › Devices and Simulators."
        case .simulatorRuntimes:
            "Los simuladores de esa versión no podrán arrancar hasta que vuelvas a descargarla en Xcode › Settings › Components."
        case .simulatorCaches:
            "Los simuladores y las vistas previas tardarán algo más en arrancar la próxima vez."
        case .packageCaches:
            "La próxima instalación de dependencias volverá a descargarlas de internet."
        case .projectDependencies:
            "Tendrás que volver a instalar dependencias o compilar (npm install, pod install, swift build…) antes de trabajar en ese proyecto."
        case .mailAttachments:
            "Ninguna: Mail vuelve a extraer el adjunto del mensaje cuando lo abres."
        case .installers, .compressedArchives:
            "Si los necesitas otra vez tendrás que volver a descargarlos. Van a la Papelera."
        case .unusedApps, .largeApps:
            "Tendrás que volver a instalar la app (y quizá introducir su licencia) si la necesitas. Todo va a la Papelera."
        case .launchAgents, .systemLaunchItems:
            "El Mac arrancará algo más rápido y con más memoria libre. Las funciones en segundo plano de esa app (actualizaciones, sincronización, icono en la barra de menús) dejarán de funcionar."
        case .appLeftovers:
            "Si vuelves a instalar la app, empezará sin tu configuración anterior. Van a la Papelera."
        case .largeFiles:
            "Si no tienes otra copia, la perderás al vaciar la Papelera."
        case .deviceBackups:
            "Si es tu única copia del dispositivo, no podrás restaurarlo desde ella. Comprueba que tienes copia en iCloud."
        case .trash:
            "Ya no podrás recuperar estos elementos."
        case .iCloudDriveDownloads:
            "Ninguna pérdida: el archivo sigue en iCloud Drive y en tus otros dispositivos. Se volverá a descargar (necesitas conexión) la próxima vez que lo abras."
        case .duplicatePhotos:
            "Ninguna: se conserva la mejor copia de cada foto."
        case .largeVideos, .screenRecordings:
            "Si no tienes otra copia, perderás el vídeo pasados 30 días."
        case .screenshots:
            "Desaparecen de tu fototeca y se borran del todo pasados 30 días."
        case .burstPhotos:
            "La foto principal de cada ráfaga se conserva; solo se van las descartadas."
        }
    }

    var systemImage: String {
        switch self {
        case .userCaches, .systemCaches: "archivebox.fill"
        case .appCaches: "app.badge.fill"
        case .userLogs, .systemLogs: "doc.text.fill"
        case .ownAppCache: "sparkles"
        case .xcodeDerivedData: "hammer.fill"
        case .xcodeDeviceSupport: "iphone.gen3"
        case .xcodeArchives: "shippingbox.fill"
        case .xcodeCaches: "books.vertical.fill"
        case .simulatorDevices: "iphone.gen3"
        case .simulatorRuntimes: "cpu.fill"
        case .simulatorCaches: "ipad.and.iphone"
        case .packageCaches: "cube.box.fill"
        case .projectDependencies: "folder.fill.badge.gearshape"
        case .mailAttachments: "paperclip"
        case .installers: "opticaldiscdrive.fill"
        case .compressedArchives: "doc.zipper"
        case .unusedApps: "moon.zzz.fill"
        case .largeApps: "square.stack.3d.up.fill"
        case .launchAgents: "person.crop.circle.badge.clock"
        case .systemLaunchItems: "gearshape.2.fill"
        case .appLeftovers: "puzzlepiece.extension.fill"
        case .largeFiles: "doc.fill"
        case .deviceBackups: "externaldrive.fill.badge.timemachine"
        case .trash: "trash.fill"
        case .iCloudDriveDownloads: "icloud.and.arrow.down.fill"
        case .duplicatePhotos: "photo.on.rectangle.angled"
        case .largeVideos: "video.fill"
        case .screenshots: "camera.viewfinder"
        case .screenRecordings: "record.circle"
        case .burstPhotos: "square.stack.3d.down.right.fill"
        }
    }

    /// `false` para categorías que no liberan espacio sino que mejoran el rendimiento.
    var measuresSpace: Bool {
        switch self {
        case .launchAgents, .systemLaunchItems: false
        default: true
        }
    }

    var module: CleaningModule {
        switch self {
        case .userCaches, .appCaches, .systemCaches, .userLogs, .systemLogs, .mailAttachments, .ownAppCache: .systemJunk
        case .xcodeDerivedData, .xcodeDeviceSupport, .xcodeArchives, .xcodeCaches, .simulatorDevices,
             .simulatorRuntimes, .simulatorCaches, .packageCaches, .projectDependencies: .developer
        case .installers, .compressedArchives: .downloads
        case .unusedApps, .largeApps: .applications
        case .launchAgents, .systemLaunchItems: .startup
        case .appLeftovers: .leftovers
        case .largeFiles, .deviceBackups: .largeFiles
        case .trash: .trash
        case .iCloudDriveDownloads: .iCloudDrive
        case .duplicatePhotos, .largeVideos, .screenshots, .screenRecordings, .burstPhotos: .photos
        }
    }
}

/// Agrupación de categorías que se muestra en la barra lateral.
nonisolated enum CleaningModule: String, Sendable, CaseIterable, Identifiable {
    case systemJunk
    case developer
    case applications
    case startup
    case downloads
    case leftovers
    case largeFiles
    case trash
    case iCloudDrive
    case photos

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .systemJunk: "Basura del sistema"
        case .developer: "Desarrollo"
        case .applications: "Aplicaciones"
        case .startup: "Inicio y rendimiento"
        case .downloads: "Descargas"
        case .leftovers: "Restos de apps"
        case .largeFiles: "Archivos grandes"
        case .trash: "Papelera"
        case .iCloudDrive: "iCloud Drive"
        case .photos: "Fototeca"
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .systemJunk: "Cachés, registros y adjuntos"
        case .developer: "Xcode, simuladores y paquetes"
        case .applications: "Poco usadas o muy pesadas"
        case .startup: "Procesos que arrancan solos"
        case .downloads: "Instaladores y comprimidos"
        case .leftovers: "Apps que ya no tienes"
        case .largeFiles: "Archivos y copias para revisar"
        case .trash: "Vaciar la Papelera"
        case .iCloudDrive: "Copias locales que puedes liberar"
        case .photos: "Duplicados, capturas y vídeos"
        }
    }

    var systemImage: String {
        switch self {
        case .systemJunk: "trash.circle.fill"
        case .developer: "hammer.circle.fill"
        case .applications: "square.grid.2x2.fill"
        case .startup: "bolt.fill"
        case .downloads: "arrow.down.circle.fill"
        case .leftovers: "puzzlepiece.fill"
        case .largeFiles: "externaldrive.fill"
        case .trash: "trash.fill"
        case .iCloudDrive: "icloud.fill"
        case .photos: "photo.stack.fill"
        }
    }

    var categories: [CleaningCategory] {
        CleaningCategory.allCases.filter { $0.module == self }
    }

    /// `false` si el módulo mejora el rendimiento en lugar de liberar espacio.
    var measuresSpace: Bool {
        categories.contains(where: \.measuresSpace)
    }
}

// MARK: - Elementos y resultados

/// Un elemento candidato a eliminarse.
nonisolated struct ScanItem: Sendable, Identifiable, Hashable {
    /// Ruta absoluta en macOS o `localIdentifier` de `PHAsset` en iOS.
    let id: String
    let displayName: String
    /// Ubicación legible (por ejemplo, `~/Library/Caches`).
    let location: String
    let category: CleaningCategory
    /// Bytes realmente asignados en disco (nunca el tamaño lógico).
    let allocatedBytes: Int64
    /// Bytes que se liberarían de verdad. En APFS excluye los bloques compartidos con clones.
    let reclaimableBytes: Int64
    let lastModified: Date?
    let risk: RiskLevel
    /// Por qué tiene ese riesgo y qué pasa si se borra.
    let reason: String
    var removal: RemovalMethod
    /// Datos extra para la fila (por ejemplo, "iOS 18.2 · iPhone 16").
    var detail: String? = nil
}

nonisolated struct ScanSummary: Sendable {
    let items: [ScanItem]
    let entriesVisited: Int
    let duration: Duration
    /// Categorías que no se pudieron analizar por falta de permisos.
    let inaccessibleCategories: Set<CleaningCategory>

    var reclaimableBytes: Int64 {
        items.reduce(0) { $0 + $1.reclaimableBytes }
    }
}

nonisolated struct CleaningReport: Sendable {
    /// Bytes liberados de inmediato.
    let reclaimedBytes: Int64
    /// Bytes movidos a la Papelera (se liberan al vaciarla).
    let trashedBytes: Int64
    let failures: [String]
    /// Elementos de inicio que se desactivaron.
    var disabledStartupItems = 0
}

nonisolated enum ScanProgress: Sendable {
    case started(CleaningCategory)
    case finished(CleaningCategory, bytes: Int64)
    case metrics(entriesVisited: Int, bytes: Int64)
}

/// Contrato común de los motores de limpieza de cada plataforma.
nonisolated protocol CleaningEngine: Sendable {
    var supportedCategories: [CleaningCategory] { get }

    /// Analiza solo `categories`, emitiendo progreso en `progress`. El motor no cierra el stream.
    func scan(categories: Set<CleaningCategory>, progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary

    /// Elimina los elementos indicados según su `removal`.
    func clean(_ items: [ScanItem]) async throws -> CleaningReport
}

extension CleaningEngine {
    var supportedModules: [CleaningModule] {
        CleaningModule.allCases.filter { module in
            module.categories.contains(where: supportedCategories.contains)
        }
    }
}

// MARK: - Uso del disco

nonisolated struct DiskUsage: Sendable {
    let totalBytes: Int64
    /// Libre de verdad ahora mismo.
    let availableBytes: Int64
    /// Libre contando el espacio purgable (instantáneas, cachés del sistema…).
    let availableForImportantUsageBytes: Int64

    var usedBytes: Int64 { totalBytes - availableBytes }
    var purgeableBytes: Int64 { max(0, availableForImportantUsageBytes - availableBytes) }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }

    static func current() -> DiskUsage? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]), let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity else {
            return nil
        }
        return DiskUsage(
            totalBytes: Int64(total),
            availableBytes: Int64(available),
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage ?? Int64(available)
        )
    }
}
