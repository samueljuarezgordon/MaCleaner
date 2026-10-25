#if DEBUG
import SwiftUI

/// Motor de ejemplo para las vistas previas: devuelve resultados al instante.
nonisolated struct SampleCleaningEngine: CleaningEngine {
    var supportedCategories: [CleaningCategory] {
        CleaningCategory.allCases.filter { $0.module != .photos && $0.module != .iCloudDrive && $0 != .ownAppCache }
    }

    func scan(categories: Set<CleaningCategory>, progress: AsyncStream<ScanProgress>.Continuation) async throws -> ScanSummary {
        ScanSummary(items: Self.items.filter { categories.contains($0.category) }, entriesVisited: 1_284_512, duration: .seconds(14), inaccessibleCategories: [.mailAttachments])
    }

    func clean(_ items: [ScanItem]) async throws -> CleaningReport {
        CleaningReport(reclaimedBytes: items.reduce(0) { $0 + $1.reclaimableBytes }, trashedBytes: 0, failures: [])
    }

    private static let gigabyte: Int64 = 1_000_000_000

    static let items: [ScanItem] = [
        item("iPhone 16 Pro", .simulatorDevices, 4.2, .safe, "No lo arrancas desde hace 5 meses. Perderás sus apps y datos de prueba, pero puedes crear otro igual en Xcode.", removal: .simulatorDevice(udid: "A"), detail: "iOS 18.2 · usado hace 5 meses"),
        item("iPad Air", .simulatorDevices, 1.1, .moderate, "Lo usaste ayer. Perderás las apps instaladas, cuentas de prueba y ajustes de este simulador.", removal: .simulatorDevice(udid: "B"), detail: "iOS 26.0 · usado ayer"),
        item("iOS 17.5 (21F79)", .simulatorRuntimes, 7.8, .safe, "Ningún simulador lo usa. Si algún día lo necesitas, Xcode vuelve a descargarlo (7,8 GB).", removal: .simulatorRuntime(identifier: "R"), detail: "ningún simulador lo usa"),
        item("MiApp", .xcodeDerivedData, 3.4, .safe, "Productos de compilación de Xcode. La próxima compilación de MiApp tardará algo más."),
        item("Cleaner", .projectDependencies, 0.9, .moderate, "Proyecto activo: tendrás que ejecutar «npm install» para volver a trabajar en él.", detail: "node_modules"),
        item("Google Chrome", .userCaches, 1.6, .safe, "Caché temporal. La app la regenerará cuando la necesite."),
        item("Slack · Cache", .appCaches, 0.6, .moderate, "Slack está abierta. Ciérrala antes de limpiar; después es seguro."),
        item("Xcode_26.dmg", .installers, 8.1, .moderate, "Instalador. Si ya instalaste la app, no lo necesitas; puedes volver a descargarlo.", removal: .moveToTrash),
        item("iPhone de Sam", .deviceBackups, 22.4, .high, "Copia de seguridad de iPhone de Sam. Podría ser la única forma de restaurar ese dispositivo.", removal: .moveToTrash, detail: "iPhone 15 Pro · copia hace 2 meses"),
        item("GameHub", .unusedApps, 5.6, .moderate, "No la usas desde hace 6 meses. Para reinstalarla necesitarás su instalador. También se moverán a la Papelera 3 carpetas de datos (5,4 GB).", removal: .uninstallApp(relatedPaths: []), detail: "v0.8 · usada hace 6 meses · 5,4 GB de datos"),
        item("Google Chrome", .largeApps, 1.5, .high, "La usaste la semana pasada: parece que la usas a menudo.", removal: .uninstallApp(relatedPaths: []), detail: "v155 · abierta la semana pasada"),
        item("Docker socket", .systemLaunchItems, 0, .moderate, "No hay ninguna app instalada de este fabricante: probablemente es un resto de una app que desinstalaste.", removal: .systemLaunchItem(label: "com.docker.socket"), detail: "Al arrancar el Mac · com.docker.socket"),
        item("Microsoft AutoUpdate", .systemLaunchItems, 0, .moderate, "Actualizador de Microsoft AutoUpdate. Sin él, buscará actualizaciones al abrir las apps.", removal: .systemLaunchItem(label: "com.microsoft.update.agent"), detail: "Cada 1 h · cargado"),
        item("Steam", .launchAgents, 0, .high, "Puede ser necesario para que Steam funcione. Quítalo solo si sabes qué hace.", removal: .launchAgent(label: "com.valvesoftware.steamclean"), detail: "Al iniciar sesión · cargado"),
        item("Vacaciones.mov", .largeFiles, 3.2, .high, "Archivo personal. Lo modificaste por última vez hace 1 año. Decide tú si lo necesitas; irá a la Papelera.", removal: .moveToTrash),
    ]

    private static func item(
        _ name: String,
        _ category: CleaningCategory,
        _ gigabytes: Double,
        _ risk: RiskLevel,
        _ reason: String,
        removal: RemovalMethod = .delete,
        detail: String? = nil
    ) -> ScanItem {
        let bytes = Int64(gigabytes * Double(gigabyte))
        return ScanItem(
            id: "/sample/\(category.rawValue)/\(name)", displayName: name, location: "~/Library",
            category: category, allocatedBytes: bytes, reclaimableBytes: bytes,
            lastModified: .now.addingTimeInterval(-86_400 * 40), risk: risk, reason: reason,
            removal: removal, detail: detail
        )
    }
}

extension CleanerViewModel {
    /// Modelo con resultados de ejemplo ya cargados.
    static func sample() -> CleanerViewModel {
        let model = CleanerViewModel(engine: SampleCleaningEngine())
        model.loadForPreview(ScanSummary(
            items: SampleCleaningEngine.items, entriesVisited: 1_284_512,
            duration: .seconds(14), inaccessibleCategories: [.mailAttachments]
        ))
        return model
    }
}

private struct SamplePreview<Content: View>: View {
    @ViewBuilder let content: (CleanerViewModel) -> Content
    @State private var model = CleanerViewModel.sample()

    var body: some View {
        content(model)
    }
}

#Preview("Antes de analizar") {
    ContentView(viewModel: CleanerViewModel(engine: SampleCleaningEngine()))
        .frame(width: 1180, height: 1100)
}

#Preview("Resultados") {
    SamplePreview { ContentView(viewModel: $0) }
        .frame(width: 1100, height: 760)
}

#Preview("Desarrollo") {
    SamplePreview { model in
        NavigationStack {
            ModuleDetailView(viewModel: model, module: .developer)
        }
    }
    .frame(width: 1100, height: 760)
}

#Preview("Inicio") {
    SamplePreview { model in
        NavigationStack {
            ModuleDetailView(viewModel: model, module: .startup)
        }
    }
    .frame(width: 1100, height: 700)
}

#Preview("Revisión") {
    SamplePreview { model in
        CleanReviewSheet(viewModel: model)
            .task { model.select(upTo: .high) }
    }
}
#endif
