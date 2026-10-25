import QuickLook
import SwiftUI

/// Revisión detallada de un módulo: cada categoría con su explicación y cada elemento con
/// su riesgo. El inspector lateral explica a fondo lo seleccionado.
struct ModuleDetailView: View {
    let viewModel: CleanerViewModel
    let module: CleaningModule

    @State private var highlighted: Set<ScanItem.ID> = []
    @State private var riskFilter: RiskLevel?
    @State private var searchText = ""
    #if os(macOS)
    @State private var showsInspector = true
    #else
    // En iPhone el inspector es una hoja: solo se abre al tocar un elemento.
    @State private var showsInspector = false
    #endif
    @State private var quickLookURL: URL?
    @AppStorage(Preferences.sortOrderKey) private var sortOrder: ItemSortOrder = .size

    var body: some View {
        content
            .navigationTitle(module.title)
            .navigationSubtitleIfAvailable(module.subtitle)
            .searchable(text: $searchText, prompt: "Buscar en \(String(localized: module.title))")
            .toolbar {
                ToolbarItem {
                    #if os(macOS)
                    riskPicker
                        .pickerStyle(.segmented)
                        .help("Filtrar por nivel de riesgo")
                    #else
                    Menu("Filtrar", systemImage: riskFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") {
                        riskPicker.pickerStyle(.inline)
                    }
                    #endif
                }
                ToolbarItem {
                    Menu("Ordenar", systemImage: "arrow.up.arrow.down") {
                        Picker("Ordenar por", selection: $sortOrder) {
                            ForEach(ItemSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    .help("Ordenar elementos")
                }
                ToolbarItem(placement: .primaryAction) {
                    ScanToolbarButton(viewModel: viewModel)
                }
                ToolbarItem {
                    Button("Información", systemImage: "sidebar.trailing") {
                        showsInspector.toggle()
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .help("Mostrar u ocultar los detalles (⌥⌘I)")
                }
            }
            .inspector(isPresented: $showsInspector) {
                ItemInspector(viewModel: viewModel, module: module, items: highlighted.compactMap(viewModel.item(withID:)))
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
            }
            .quickLookPreview($quickLookURL)
    }

    private var riskPicker: some View {
        Picker("Riesgo", selection: $riskFilter) {
            Text("Todos").tag(RiskLevel?.none)
            ForEach(RiskLevel.allCases) { risk in
                Text(risk.title).tag(RiskLevel?.some(risk))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let groups = filteredGroups
        if !viewModel.hasResults {
            ContentUnavailableView {
                Label(viewModel.phase == .scanning ? "Analizando…" : "Aún no has analizado", systemImage: module.systemImage)
            } description: {
                Text(module.categories.first?.explanation ?? "")
            } actions: {
                if viewModel.phase != .scanning {
                    Button("Analizar solo \(String(localized: module.title))") {
                        viewModel.startScan(only: Set(viewModel.supportedCategories(in: module)))
                    }
                    .buttonStyle(.glassProminent)
                } else {
                    ProgressView()
                }
            }
        } else if viewModel.groups(in: module).isEmpty {
            ContentUnavailableView {
                Label("Nada que limpiar aquí", systemImage: "checkmark.circle")
            } description: {
                Text(inaccessibleNote ?? "No se encontró nada en esta sección.")
            } actions: {
                Button("Analizar solo \(String(localized: module.title))") {
                    viewModel.startScan(only: Set(viewModel.supportedCategories(in: module)))
                }
                .disabled(viewModel.phase == .scanning)
            }
        } else {
            List(selection: $highlighted) {
                Section {
                    ModuleHeader(viewModel: viewModel, module: module)
                }
                if groups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { item in
                            ItemRow(
                                item: item,
                                isSelected: viewModel.isSelected(item),
                                toggle: { viewModel.setSelected(!viewModel.isSelected(item), for: item) }
                            )
                            .tag(item.id)
                            #if os(iOS)
                            // En iOS la selección de listas solo funciona en modo edición: un
                            // toque abre los detalles.
                            .onTapGesture {
                                highlighted = [item.id]
                                showsInspector = true
                            }
                            #endif
                        }
                    } header: {
                        CategoryHeader(viewModel: viewModel, group: group)
                    }
                }
            }
            .contextMenu(forSelectionType: ScanItem.ID.self) { ids in
                ItemContextMenu(viewModel: viewModel, items: ids.compactMap(viewModel.item(withID:))) { url in
                    quickLookURL = url
                }
            } primaryAction: { ids in
                // Doble clic: incluir o quitar de la limpieza.
                let items = ids.compactMap(viewModel.item(withID:))
                viewModel.setSelected(viewModel.selectionState(of: items) != .all, for: items)
            }
            .onKeyPress(.space) {
                // Espacio: Vista rápida, como en el Finder.
                guard let item = highlighted.first.flatMap(viewModel.item(withID:)), PlatformActions.isLocalFile(item) else {
                    return .ignored
                }
                quickLookURL = quickLookURL == nil ? URL(fileURLWithPath: item.id) : nil
                return .handled
            }
        }
    }

    private var inaccessibleNote: String? {
        let blocked = module.categories.filter(viewModel.inaccessibleCategories.contains)
        guard !blocked.isEmpty else { return nil }
        #if os(macOS)
        let hint = "Concede «Acceso total al disco» y vuelve a analizar."
        #else
        let hint = "Elige carpetas en Ajustes (o permite el acceso a Fotos) y vuelve a analizar."
        #endif
        return "No se pudo acceder a \(blocked.map { String(localized: $0.title) }.formatted(.list(type: .and))). \(hint)"
    }

    /// Grupos con el filtro de riesgo, la búsqueda y el orden aplicados.
    private var filteredGroups: [CleanerViewModel.CategoryGroup] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return viewModel.groups(in: module).compactMap { group in
            let items = group.items.filter { item in
                (riskFilter == nil || item.risk == riskFilter)
                    && (query.isEmpty
                        || item.displayName.localizedStandardContains(query)
                        || item.location.localizedStandardContains(query)
                        || (item.detail?.localizedStandardContains(query) ?? false))
            }
            guard !items.isEmpty else { return nil }
            return CleanerViewModel.CategoryGroup(
                category: group.category,
                items: items.sorted(by: sortOrder.areInIncreasingOrder),
                totalBytes: items.reduce(0) { $0 + $1.reclaimableBytes }
            )
        }
    }
}

// MARK: - Menú contextual

/// Acciones sobre uno o varios elementos (clic secundario).
struct ItemContextMenu: View {
    let viewModel: CleanerViewModel
    let items: [ScanItem]
    let quickLook: (URL) -> Void

    var body: some View {
        if !items.isEmpty {
            let included = viewModel.selectionState(of: items) == .all
            Button(included ? "Quitar de la limpieza" : "Incluir en la limpieza",
                   systemImage: included ? "minus.circle" : "checkmark.circle") {
                viewModel.setSelected(!included, for: items)
            }

            #if os(macOS)
            let files = items.filter(PlatformActions.isLocalFile)
            if !files.isEmpty {
                Divider()
                Button("Mostrar en el Finder", systemImage: "folder") {
                    PlatformActions.revealInFinder(files)
                }
                if files.count == 1, let file = files.first {
                    Button("Vista rápida", systemImage: "eye") {
                        quickLook(URL(fileURLWithPath: file.id))
                    }
                }
                Button(files.count == 1 ? "Copiar ruta" : "Copiar rutas", systemImage: "doc.on.doc") {
                    PlatformActions.copy(files.map(\.id).joined(separator: "\n"))
                }
            }
            #endif

            Divider()
            Button(items.count == 1 ? "Ignorar siempre" : "Ignorar \(items.count) elementos siempre", systemImage: "eye.slash") {
                viewModel.ignore(items)
            }
        }
    }
}

// MARK: - Cabeceras

private struct ModuleHeader: View {
    let viewModel: CleanerViewModel
    let module: CleaningModule

    var body: some View {
        let stats = viewModel.stats(for: module)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ModuleIcon(module: module, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    if module.measuresSpace {
                        Text(stats.totalBytes.byteString)
                            .font(.title.bold().monospacedDigit())
                        Text("\(stats.itemCount) elementos · \(viewModel.selectedBytes(in: module).byteString) seleccionados")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(stats.itemCount) procesos de inicio")
                            .font(.title.bold().monospacedDigit())
                        Text("\(viewModel.selectedCount(in: module)) seleccionados para desactivar")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Volver a analizar", systemImage: "arrow.clockwise") {
                    viewModel.startScan(only: Set(viewModel.supportedCategories(in: module)))
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(viewModel.phase == .scanning || viewModel.phase == .cleaning)
                .help("Volver a analizar solo \(String(localized: module.title)); el resto de resultados se conserva")
                Menu("Seleccionar") {
                    Button("Solo lo seguro") { viewModel.select(upTo: .safe, in: module) }
                    Button("Seguro y a revisar") { viewModel.select(upTo: .moderate, in: module) }
                    Button("Todo, incluido riesgo alto") { viewModel.select(upTo: .high, in: module) }
                    Divider()
                    Button("Nada") { viewModel.select(upTo: nil, in: module) }
                }
                .fixedSize()
            }
            if module.measuresSpace {
                RiskBar(stats: stats, height: 10)
                RiskLegend(stats: stats, hidesEmpty: true)
            }
            #if os(macOS)
            if module == .startup {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Las apps que se abren al iniciar sesión (Ítems de inicio) se gestionan en Ajustes del Sistema.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Abrir Ítems de inicio…", action: PlatformActions.openLoginItemsSettings)
                }
            }
            #endif
        }
        .padding(.vertical, 8)
    }
}

private struct CategoryHeader: View {
    let viewModel: CleanerViewModel
    let group: CleanerViewModel.CategoryGroup
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SelectionCheckbox(state: viewModel.selectionState(of: group.items)) { isSelected in
                    viewModel.setSelected(isSelected, for: group.items)
                }
                CategoryIcon(category: group.category, size: 26)
                Text(group.category.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(group.items.count)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.fill.tertiary, in: .capsule)
                Spacer()
                if group.category.measuresSpace {
                    Text(group.totalBytes.byteString)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                Button(isExpanded ? "Ocultar explicación" : "¿Qué es esto?", systemImage: isExpanded ? "chevron.up" : "info.circle") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(isExpanded ? "Ocultar explicación" : "¿Qué es esto y qué pasa si lo borro?")
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ExplanationRow(title: "Qué es", systemImage: "questionmark.circle.fill", text: Text(group.category.explanation), tint: .blue)
                    ExplanationRow(title: "Si lo quitas", systemImage: "arrow.uturn.backward.circle.fill", text: Text(group.category.consequence), tint: .orange)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary, in: .rect(cornerRadius: 10))
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text(group.category.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

// MARK: - Fila

private struct ItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let toggle: () -> Void
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isSelected ? "Quitar de la limpieza" : "Incluir en la limpieza")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail ?? item.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isCompact {
                Image(systemName: item.risk.systemImage)
                    .foregroundStyle(item.risk.color)
                    .accessibilityLabel(Text("Riesgo: \(item.risk.title)"))
            } else {
                RiskBadge(risk: item.risk)
            }
            if item.category.measuresSpace {
                Text(item.reclaimableBytes.byteString)
                    .font(.callout.monospacedDigit())
                    .frame(minWidth: isCompact ? 56 : 72, alignment: .trailing)
            } else {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.yellow)
                    .frame(minWidth: 72, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: isSelected ? "Quitar de la limpieza" : "Incluir en la limpieza", toggle)
    }
}

// MARK: - Subtítulo

private extension View {
    @ViewBuilder
    func navigationSubtitleIfAvailable(_ subtitle: LocalizedStringResource) -> some View {
        #if os(macOS)
        navigationSubtitle(Text(subtitle))
        #else
        self
        #endif
    }
}
