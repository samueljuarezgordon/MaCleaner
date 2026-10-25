import SwiftUI

/// Pantalla principal: invita a analizar, muestra el progreso y resume lo encontrado.
struct OverviewView: View {
    let viewModel: CleanerViewModel
    @Binding var destination: SidebarDestination?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var horizontalPadding: CGFloat { sizeClass == .compact ? 16 : 32 }
    #else
    private let horizontalPadding: CGFloat = 32
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                switch viewModel.phase {
                case .idle:
                    IdleHero(viewModel: viewModel)
                case .scanning:
                    ScanningHero(viewModel: viewModel)
                case .results:
                    ResultsSummary(viewModel: viewModel, destination: $destination)
                case .cleaning:
                    ScanRing(
                        title: "Limpiando",
                        value: viewModel.selectedStats.totalBytes.byteString,
                        subtitle: "\(viewModel.selectedStats.itemCount) elementos"
                    )
                    .padding(.top, 60)
                case .done:
                    CleaningReportView(viewModel: viewModel)
                }
            }
            .padding(horizontalPadding)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Análisis inteligente")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ScanToolbarButton(viewModel: viewModel)
            }
        }
    }
}

/// Botón de la barra de herramientas para analizar o cancelar.
struct ScanToolbarButton: View {
    let viewModel: CleanerViewModel

    var body: some View {
        if viewModel.phase == .scanning {
            Button("Detener", systemImage: "stop.fill", action: viewModel.cancel)
        } else {
            Button(viewModel.hasResults ? "Volver a analizar" : "Analizar", systemImage: "arrow.clockwise", action: viewModel.startScan)
                .disabled(viewModel.phase == .cleaning || viewModel.enabledCategories.isEmpty)
                .help(viewModel.enabledCategories.isEmpty ? "No hay nada elegido para analizar" : "Analizar lo elegido (⌘R)")
        }
    }
}

// MARK: - Antes de analizar

private struct IdleHero: View {
    let viewModel: CleanerViewModel

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppTheme.scanGradient)
                .padding(.top, 24)

            VStack(spacing: 8) {
                Text("Recupera espacio sin sustos")
                    .font(.largeTitle.bold())
                Text("MaCleaner analiza a fondo tu disco y te explica qué es cada cosa, para qué servía y qué riesgo tiene borrarla. No se elimina nada hasta que tú lo revises y confirmes.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            Button(action: viewModel.startScan) {
                Text("Analizar")
                    .font(.title2.weight(.semibold))
                    .frame(width: 180, height: 44)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.enabledCategories.isEmpty)

            if viewModel.enabledCategories.isEmpty {
                Text("Elige abajo qué quieres analizar.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let usage = viewModel.diskUsage {
                DiskUsageCard(usage: usage)
            }

            #if os(iOS)
            FolderAccessPrompt()
            #endif

            ModuleGlossary(viewModel: viewModel)
        }
    }
}

/// Selector de qué se analiza: un toque activa o desactiva un módulo y su menú permite
/// elegir categoría por categoría. La elección se guarda entre sesiones.
private struct ModuleGlossary: View {
    let viewModel: CleanerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Qué analizar")
                    .font(.headline)
                Spacer()
                Button("Todo") { viewModel.setEnabled(true, for: allCategories) }
                    .disabled(viewModel.disabledCategories.isDisjoint(with: allCategories))
                Button("Nada") { viewModel.setEnabled(false, for: allCategories) }
                    .disabled(viewModel.enabledCategories.isEmpty)
            }
            .buttonStyle(.borderless)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 20, alignment: .topLeading)],
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(viewModel.modules) { module in
                    ScopeModuleCell(viewModel: viewModel, module: module)
                        // Sin esto, cada celda se centra en su columna y las filas quedan escalonadas.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Text("Se analizarán \(viewModel.enabledCategories.count) de \(allCategories.count) categorías. Toca un módulo para incluirlo o quitarlo; usa su menú para elegir partes concretas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private var allCategories: [CleaningCategory] {
        viewModel.modules.flatMap(viewModel.supportedCategories(in:))
    }
}

private struct ScopeModuleCell: View {
    let viewModel: CleanerViewModel
    let module: CleaningModule

    var body: some View {
        let state = viewModel.scanSelectionState(of: module)
        let categories = viewModel.supportedCategories(in: module)
        HStack(alignment: .top, spacing: 12) {
            Button {
                viewModel.setEnabled(state != .all, for: categories)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    ModuleIcon(module: module, size: 32)
                        .saturation(state == .none ? 0 : 1)
                        .opacity(state == .none ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(state == .none ? .secondary : .primary)
                        Text(subtitle(state: state, categories: categories))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: symbol(for: state))
                        .font(.title3)
                        .foregroundStyle(state == .none ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(module.title))
            .accessibilityValue(Text(state == .none ? "No se analiza" : state == .all ? "Se analiza" : "Se analiza en parte"))

            if categories.count > 1 {
                Menu {
                    ForEach(categories) { category in
                        Toggle(isOn: Binding(
                            get: { viewModel.isEnabled(category) },
                            set: { viewModel.setEnabled($0, for: [category]) }
                        )) {
                            Label {
                                Text(category.title)
                            } icon: {
                                Image(systemName: category.systemImage)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Elegir qué partes de \(String(localized: module.title)) analizar")
            }
        }
    }

    private func subtitle(state: CleanerViewModel.SelectionState, categories: [CleaningCategory]) -> String {
        switch state {
        case .all: String(localized: module.subtitle)
        case .none: String(localized: "No se analizará")
        case .some:
            String(localized: "Solo \(categories.filter(viewModel.isEnabled).map { String(localized: $0.title) }.formatted(.list(type: .and)))")
        }
    }

    private func symbol(for state: CleanerViewModel.SelectionState) -> String {
        switch state {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
    }
}

// MARK: - Analizando

private struct ScanningHero: View {
    let viewModel: CleanerViewModel

    var body: some View {
        VStack(spacing: 28) {
            ScanRing(
                title: "Encontrado",
                value: viewModel.bytesFound.byteString,
                subtitle: "\(viewModel.entriesVisited.formatted()) archivos analizados"
            )
            .padding(.top, 20)

            VStack(spacing: 4) {
                Text("Analizando tu disco…")
                    .font(.title2.bold())
                Text("\(viewModel.completedCategoryCount) de \(viewModel.totalCategoryCount) categorías completadas")
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(viewModel.scanScope) { category in
                    CategoryProgressRow(category: category, status: viewModel.categoryStatus[category] ?? .pending)
                }
            }
        }
    }
}

private struct CategoryProgressRow: View {
    let category: CleaningCategory
    let status: CleanerViewModel.CategoryStatus

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: category, tint: tint, size: 26)
            Text(category.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 4)
            switch status {
            case .pending:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.tertiary)
            case .scanning:
                ProgressView()
                    .controlSize(.small)
            case .done(let bytes):
                Text(bytes > 0 ? bytes.byteString : "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.fill.quaternary, in: .rect(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch status {
        case .pending: .secondary
        case .scanning: .accentColor
        case .done: .green
        }
    }
}

// MARK: - Resultados

private struct ResultsSummary: View {
    let viewModel: CleanerViewModel
    @Binding var destination: SidebarDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Puedes liberar hasta")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(viewModel.totalStats.totalBytes.byteString)
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                if let duration = viewModel.lastScanDuration, let date = viewModel.lastScanDate {
                    Text("Análisis \(date.formatted(.relative(presentation: .named))) · \(viewModel.totalStats.itemCount) elementos en \(viewModel.entriesVisited.formatted()) archivos analizados en \(duration.formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                RiskBar(stats: viewModel.totalStats, height: 12)
                    .padding(.top, 4)
                RiskLegend(stats: viewModel.totalStats)
            }

            RiskExplainer()

            SelectionPresets(viewModel: viewModel)

            if !viewModel.inaccessibleCategories.isEmpty {
                InaccessibleBanner(categories: viewModel.inaccessibleCategories, destination: $destination)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                ForEach(viewModel.modules) { module in
                    ModuleCard(viewModel: viewModel, module: module) {
                        destination = .module(module)
                    }
                }
            }
        }
    }
}

/// Explica en una línea qué significa cada color de riesgo.
private struct RiskExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(RiskLevel.allCases) { risk in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RiskBadge(risk: risk)
                        .frame(minWidth: 110, alignment: .leading)
                    Text(risk.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

/// Atajos para seleccionar por nivel de riesgo.
private struct SelectionPresets: View {
    let viewModel: CleanerViewModel

    var body: some View {
        // En pantallas estrechas los botones pasan a una columna.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text("Seleccionar:")
                    .foregroundStyle(.secondary)
                buttons
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Seleccionar:")
                    .foregroundStyle(.secondary)
                HStack { buttons }
            }
        }
        .buttonStyle(.glass)
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Solo lo seguro") { viewModel.select(upTo: .safe) }
        Button("Seguro y a revisar") { viewModel.select(upTo: .moderate) }
        Button("Nada") { viewModel.select(upTo: nil) }
    }
}

private struct InaccessibleBanner: View {
    let categories: Set<CleaningCategory>
    @Binding var destination: SidebarDestination?

    #if os(macOS)
    static let permissionHint = String(localized: "Concede «Acceso total al disco» para un análisis completo.")
    #else
    static let permissionHint = String(localized: "Elige carpetas en Ajustes y permite el acceso a Fotos para un análisis completo.")
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hay zonas que no se pudieron analizar")
                    .font(.headline)
                Text("Sin permiso para: \(categories.sorted { $0.rawValue < $1.rawValue }.map { String(localized: $0.title) }.formatted(.list(type: .and))). \(Self.permissionHint)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #if os(macOS)
                Button("Revisar permisos") { destination = .maintenance }
                    .padding(.top, 4)
                #else
                Button("Elegir carpetas o permisos") { destination = .settings }
                    .padding(.top, 4)
                #endif
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 16))
    }
}

private struct ModuleCard: View {
    let viewModel: CleanerViewModel
    let module: CleaningModule
    let open: () -> Void

    var body: some View {
        let stats = viewModel.stats(for: module)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ModuleIcon(module: module, size: 40)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title)
                        .font(.headline)
                    Text(module.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(summary(stats))
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(stats.itemCount > 0 ? .primary : .secondary)
                if stats.totalBytes > 0 {
                    RiskBar(stats: stats)
                }
                if stats.itemCount > 0 {
                    Text("\(viewModel.selectedCount(in: module)) de \(stats.itemCount) seleccionados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        .accessibilityHint("Abre la revisión detallada")
    }

    private func summary(_ stats: CleanerViewModel.ModuleStats) -> String {
        guard stats.itemCount > 0 else {
            return viewModel.scanSelectionState(of: module) == .none
                ? String(localized: "No analizado")
                : String(localized: "Nada que limpiar")
        }
        return module.measuresSpace ? stats.totalBytes.byteString : String(localized: "\(stats.itemCount) procesos")
    }
}

// MARK: - Después de limpiar

private struct CleaningReportView: View {
    let viewModel: CleanerViewModel

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: viewModel.phase)
                .padding(.top, 40)

            if let report = viewModel.lastReport {
                VStack(spacing: 6) {
                    Text("Limpieza completada")
                        .font(.largeTitle.bold())
                    Text("Liberados \(report.reclaimedBytes.byteString)")
                        .font(.title2.monospacedDigit())
                    if report.trashedBytes > 0 {
                        Text("\(report.trashedBytes.byteString) se movieron a la Papelera. El espacio se liberará cuando la vacíes.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if report.disabledStartupItems > 0 {
                        Label("\(report.disabledStartupItems) procesos de inicio desactivados", systemImage: "bolt.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                }

                if !report.failures.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(report.failures.count) elementos no se pudieron eliminar", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        ForEach(report.failures, id: \.self) { failure in
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(in: .rect(cornerRadius: 16))
                }
            }

            HStack {
                #if os(macOS)
                if (viewModel.lastReport?.trashedBytes ?? 0) > 0 {
                    Button("Abrir la Papelera", systemImage: "trash", action: PlatformActions.openTrash)
                        .buttonStyle(.glass)
                }
                #endif
                if viewModel.hasResults {
                    Button("Ver lo que queda", action: viewModel.dismissReport)
                        .buttonStyle(.glass)
                }
                Button("Analizar de nuevo", action: viewModel.startScan)
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
        }
    }
}
