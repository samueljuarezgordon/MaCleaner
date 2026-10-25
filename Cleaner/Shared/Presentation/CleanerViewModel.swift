import Foundation
import Observation

/// Estado de presentación compartido por macOS e iOS. No sabe qué motor tiene debajo.
@MainActor
@Observable
final class CleanerViewModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaning
        case done
    }

    enum CategoryStatus: Equatable {
        case pending
        case scanning
        case done(bytes: Int64)
    }

    struct CategoryGroup: Identifiable {
        let category: CleaningCategory
        let items: [ScanItem]
        let totalBytes: Int64
        var id: CleaningCategory { category }
    }

    struct ModuleStats {
        var totalBytes: Int64 = 0
        var itemCount = 0
        var bytesByRisk: [RiskLevel: Int64] = [:]

        func bytes(for risk: RiskLevel) -> Int64 { bytesByRisk[risk] ?? 0 }
    }

    // MARK: - Estado público

    let modules: [CleaningModule]
    private(set) var phase: Phase = .idle
    private(set) var diskUsage: DiskUsage?
    private(set) var categoryStatus: [CleaningCategory: CategoryStatus] = [:]
    private(set) var entriesVisited = 0
    private(set) var bytesFound: Int64 = 0
    private(set) var lastScanDuration: Duration?
    private(set) var lastReport: CleaningReport?
    private(set) var inaccessibleCategories: Set<CleaningCategory> = []
    private(set) var groupsByModule: [CleaningModule: [CategoryGroup]] = [:]
    private(set) var statsByModule: [CleaningModule: ModuleStats] = [:]
    private(set) var totalStats = ModuleStats()
    private(set) var selection: Set<ScanItem.ID> = []
    private(set) var selectedStats = ModuleStats()
    var errorMessage: String?
    /// Muestra la hoja de revisión antes de limpiar (desde la barra o el menú).
    var isReviewingClean = false
    private(set) var lastScanDate: Date?
    /// Categorías que el usuario ha desactivado en «Qué analizar». Se guardan entre sesiones.
    private(set) var disabledCategories: Set<CleaningCategory> = Preferences.disabledCategories
    /// Categorías del análisis en curso o del último, en el orden de la barra lateral.
    private(set) var scanScope: [CleaningCategory] = []
    /// Elementos que el usuario pidió ignorar siempre. Se guardan entre sesiones.
    private(set) var excludedIDs: Set<ScanItem.ID> = Set(UserDefaults.standard.stringArray(forKey: Preferences.exclusionsKey) ?? [])

    var hasResults: Bool { !items.isEmpty }

    // MARK: - Privado

    private let engine: any CleaningEngine
    private var items: [ScanItem] = []
    private var itemsByID: [ScanItem.ID: ScanItem] = [:]
    private var activeTask: Task<Void, Never>?

    init(engine: any CleaningEngine = CleaningEngineFactory.makeDefault()) {
        self.engine = engine
        self.modules = engine.supportedModules
        refreshDiskUsage()
    }

    // MARK: - Escaneo

    /// Analiza las categorías activadas en «Qué analizar».
    func startScan() {
        startScan(only: enabledCategories)
    }

    /// Analiza solo `scope`. Los resultados de las demás categorías se conservan.
    func startScan(only scope: Set<CleaningCategory>) {
        let scope = scope.intersection(engine.supportedCategories)
        guard !scope.isEmpty else { return }
        activeTask?.cancel()
        phase = .scanning
        entriesVisited = 0
        bytesFound = 0
        errorMessage = nil
        lastReport = nil
        scanScope = modules.flatMap(\.categories).filter(scope.contains)
        categoryStatus = Dictionary(uniqueKeysWithValues: scanScope.map { ($0, .pending) })

        activeTask = Task {
            let (stream, continuation) = AsyncStream.makeStream(
                of: ScanProgress.self,
                bufferingPolicy: .bufferingNewest(64)
            )
            // El consumo del progreso es una tarea hija estructurada: se cancela con el escaneo.
            async let consumption: Void = consume(stream)

            do {
                let summary = try await engine.scan(categories: scope, progress: continuation)
                apply(summary, scope: scope)
                phase = .results
            } catch is CancellationError {
                phase = hasResults ? .results : .idle
            } catch {
                errorMessage = error.localizedDescription
                phase = hasResults ? .results : .idle
            }
            continuation.finish()
            await consumption
            refreshDiskUsage()
        }
    }

    func cancel() {
        activeTask?.cancel()
    }

    private func consume(_ stream: AsyncStream<ScanProgress>) async {
        for await event in stream {
            switch event {
            case .started(let category):
                categoryStatus[category] = .scanning
            case .finished(let category, let bytes):
                categoryStatus[category] = .done(bytes: bytes)
            case .metrics(let entries, let bytes):
                entriesVisited = entries
                bytesFound = bytes
            }
        }
    }

    // MARK: - Limpieza

    /// Limpia la selección. Si `permanently` es `true`, lo que iría a la Papelera se borra
    /// directamente.
    func cleanSelection(permanently: Bool) {
        let selected = selectedItems().map { item in
            var item = item
            if permanently, item.removal == .moveToTrash { item.removal = .delete }
            return item
        }
        guard !selected.isEmpty else { return }
        phase = .cleaning

        activeTask = Task {
            do {
                lastReport = try await engine.clean(selected)
                let cleaned = Set(selected.map(\.id))
                apply(items: items.filter { !cleaned.contains($0.id) }, inaccessible: inaccessibleCategories)
                phase = .done
            } catch {
                errorMessage = error.localizedDescription
                phase = .results
            }
            refreshDiskUsage()
        }
    }

    func dismissReport() {
        phase = hasResults ? .results : .idle
    }

    // MARK: - Selección

    func isSelected(_ item: ScanItem) -> Bool {
        selection.contains(item.id)
    }

    func setSelected(_ isSelected: Bool, for item: ScanItem) {
        if isSelected {
            selection.insert(item.id)
        } else {
            selection.remove(item.id)
        }
        updateSelectedStats()
    }

    /// Selecciona todo lo que tenga como mucho `maxRisk` (o nada si es `nil`) en `module`,
    /// o en todos los módulos si `module` es `nil`.
    func select(upTo maxRisk: RiskLevel?, in module: CleaningModule? = nil) {
        let scope = module.map(items(in:)) ?? items
        for item in scope {
            if let maxRisk, item.risk <= maxRisk {
                selection.insert(item.id)
            } else {
                selection.remove(item.id)
            }
        }
        updateSelectedStats()
    }

    func selectedItems(in module: CleaningModule? = nil) -> [ScanItem] {
        selection.compactMap { itemsByID[$0] }.filter { module == nil || $0.category.module == module }
    }

    func selectedBytes(in module: CleaningModule) -> Int64 {
        selectedItems(in: module).reduce(0) { $0 + $1.reclaimableBytes }
    }

    func item(withID id: ScanItem.ID) -> ScanItem? {
        itemsByID[id]
    }

    // MARK: - Estado derivado

    func refreshDiskUsage() {
        diskUsage = DiskUsage.current()
    }

    private func items(in module: CleaningModule) -> [ScanItem] {
        groupsByModule[module]?.flatMap(\.items) ?? []
    }

    private func apply(_ summary: ScanSummary, scope: Set<CleaningCategory>) {
        lastScanDuration = summary.duration
        lastScanDate = .now
        entriesVisited = summary.entriesVisited

        // Lo que no se ha vuelto a analizar se conserva tal cual, con su selección.
        let kept = items.filter { !scope.contains($0.category) }
        let keptSelection = selection.intersection(kept.map(\.id))
        let fresh = summary.items.filter { !excludedIDs.contains($0.id) }
        let inaccessible = inaccessibleCategories.subtracting(scope).union(summary.inaccessibleCategories)
        apply(items: kept + fresh, inaccessible: inaccessible)

        // La selección inicial depende de la preferencia del usuario (por defecto, lo seguro).
        let policy = Preferences.defaultSelection
        selection = keptSelection.union(fresh.filter { item in policy.maxRisk.map { item.risk <= $0 } ?? false }.map(\.id))
        updateSelectedStats()
    }

    /// Los grupos y estadísticas se calculan una sola vez aquí y no en `body`.
    private func apply(items newItems: [ScanItem], inaccessible: Set<CleaningCategory>) {
        items = newItems
        itemsByID = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })
        inaccessibleCategories = inaccessible

        let byCategory = Dictionary(grouping: newItems, by: \.category)
        var groups: [CleaningModule: [CategoryGroup]] = [:]
        var stats: [CleaningModule: ModuleStats] = [:]

        for module in modules {
            groups[module] = module.categories.compactMap { category in
                guard let items = byCategory[category], !items.isEmpty else { return nil }
                return CategoryGroup(
                    category: category,
                    items: items.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
                    totalBytes: items.reduce(0) { $0 + $1.reclaimableBytes }
                )
            }
            stats[module] = Self.stats(for: groups[module]?.flatMap(\.items) ?? [])
        }

        groupsByModule = groups
        statsByModule = stats
        totalStats = Self.stats(for: newItems)
        selection.formIntersection(itemsByID.keys)
        updateSelectedStats()
    }

    private func updateSelectedStats() {
        selectedStats = Self.stats(for: selectedItems())
    }

    private static func stats(for items: [ScanItem]) -> ModuleStats {
        var stats = ModuleStats()
        for item in items {
            stats.totalBytes += item.reclaimableBytes
            stats.itemCount += 1
            stats.bytesByRisk[item.risk, default: 0] += item.reclaimableBytes
        }
        return stats
    }
}

// MARK: - Ayudas para la interfaz

extension CleanerViewModel {
    enum SelectionState {
        case none, some, all
    }

    /// Cuánto de la selección se borra definitivamente y cuánto es recuperable.
    struct RemovalBreakdown {
        var permanentBytes: Int64 = 0
        var recoverableBytes: Int64 = 0
        var highRiskItems: [ScanItem] = []
    }

    /// Categorías que se están analizando ahora mismo.
    var scanningCategories: [CleaningCategory] {
        engine.supportedCategories.filter { categoryStatus[$0] == .scanning }
    }

    /// Categorías que se analizarán al pulsar «Analizar».
    var enabledCategories: Set<CleaningCategory> {
        Set(engine.supportedCategories).subtracting(disabledCategories)
    }

    /// Categorías del motor que pertenecen a `module` (un módulo puede tener categorías de otra
    /// plataforma).
    func supportedCategories(in module: CleaningModule) -> [CleaningCategory] {
        module.categories.filter(engine.supportedCategories.contains)
    }

    func isEnabled(_ category: CleaningCategory) -> Bool {
        !disabledCategories.contains(category)
    }

    func scanSelectionState(of module: CleaningModule) -> SelectionState {
        let categories = supportedCategories(in: module)
        let enabled = categories.count(where: isEnabled)
        if enabled == 0 { return .none }
        return enabled == categories.count ? .all : .some
    }

    /// Activa o desactiva categorías en «Qué analizar».
    func setEnabled(_ isEnabled: Bool, for categories: [CleaningCategory]) {
        if isEnabled {
            disabledCategories.subtract(categories)
        } else {
            disabledCategories.formUnion(categories)
        }
        Preferences.disabledCategories = disabledCategories
    }

    var completedCategoryCount: Int {
        categoryStatus.values.filter { if case .done = $0 { true } else { false } }.count
    }

    var totalCategoryCount: Int { scanScope.count }

    func groups(in module: CleaningModule) -> [CategoryGroup] {
        groupsByModule[module] ?? []
    }

    func stats(for module: CleaningModule) -> ModuleStats {
        statsByModule[module] ?? ModuleStats()
    }

    func selectionState(of items: [ScanItem]) -> SelectionState {
        let selected = items.count { selection.contains($0.id) }
        if selected == 0 { return .none }
        return selected == items.count ? .all : .some
    }

    /// Marca o desmarca de golpe todos los elementos indicados.
    func setSelected(_ isSelected: Bool, for items: [ScanItem]) {
        let ids = items.map(\.id)
        if isSelected {
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
        updateSelectedStats()
    }

    func selectedCount(in module: CleaningModule) -> Int {
        items(in: module).count { selection.contains($0.id) }
    }

    func removalBreakdown(permanently: Bool) -> RemovalBreakdown {
        var breakdown = RemovalBreakdown()
        for item in selectedItems() {
            let recoverable = item.removal.isRecoverable && !(permanently && item.removal == .moveToTrash)
            if recoverable {
                breakdown.recoverableBytes += item.reclaimableBytes
            } else {
                breakdown.permanentBytes += item.reclaimableBytes
            }
            if item.risk == .high { breakdown.highRiskItems.append(item) }
        }
        breakdown.highRiskItems.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        return breakdown
    }
}

#if DEBUG
extension CleanerViewModel {
    /// Carga resultados de forma síncrona, para las vistas previas.
    func loadForPreview(_ summary: ScanSummary) {
        apply(summary, scope: Set(engine.supportedCategories))
        phase = .results
    }
}
#endif

// MARK: - Exclusiones

extension CleanerViewModel {
    /// Oculta los elementos ahora y en los próximos análisis.
    func ignore(_ ignored: [ScanItem]) {
        excludedIDs.formUnion(ignored.map(\.id))
        persistExclusions()
        let ids = Set(ignored.map(\.id))
        apply(items: items.filter { !ids.contains($0.id) }, inaccessible: inaccessibleCategories)
    }

    /// Vuelve a mostrar un elemento ignorado en el próximo análisis.
    func stopIgnoring(_ id: ScanItem.ID) {
        excludedIDs.remove(id)
        persistExclusions()
    }

    func clearExclusions() {
        excludedIDs.removeAll()
        persistExclusions()
    }

    private func persistExclusions() {
        UserDefaults.standard.set(excludedIDs.sorted(), forKey: Preferences.exclusionsKey)
    }
}
