import Foundation

/// Preferencias de la app guardadas en `UserDefaults`.
nonisolated enum Preferences {
    static let exclusionsKey = "excludedItemIDs"
    static let defaultSelectionKey = "defaultSelection"
    static let skipTrashKey = "skipTrashByDefault"
    static let sortOrderKey = "itemSortOrder"
    static let disabledCategoriesKey = "disabledScanCategories"

    /// Categorías que el usuario ha decidido no analizar. Se guardan las desactivadas (y no
    /// las activadas) para que las categorías nuevas de futuras versiones vengan activadas.
    static var disabledCategories: Set<CleaningCategory> {
        get {
            Set((UserDefaults.standard.stringArray(forKey: disabledCategoriesKey) ?? []).compactMap(CleaningCategory.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: disabledCategoriesKey)
        }
    }

    /// Qué se marca automáticamente al terminar un análisis.
    enum DefaultSelection: String, CaseIterable, Identifiable {
        case safe
        case moderate
        case none

        var id: Self { self }

        var title: LocalizedStringResource {
            switch self {
            case .safe: "Solo lo seguro"
            case .moderate: "Lo seguro y lo que hay que revisar"
            case .none: "Nada: lo elijo yo"
            }
        }

        var maxRisk: RiskLevel? {
            switch self {
            case .safe: .safe
            case .moderate: .moderate
            case .none: nil
            }
        }
    }

    static var defaultSelection: DefaultSelection {
        UserDefaults.standard.string(forKey: defaultSelectionKey).flatMap(DefaultSelection.init) ?? .safe
    }
}

/// Orden de los elementos dentro de cada categoría.
enum ItemSortOrder: String, CaseIterable, Identifiable {
    case size
    case name
    case date
    case risk

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .size: "Tamaño"
        case .name: "Nombre"
        case .date: "Fecha"
        case .risk: "Riesgo"
        }
    }

    func areInIncreasingOrder(_ lhs: ScanItem, _ rhs: ScanItem) -> Bool {
        switch self {
        case .size: lhs.reclaimableBytes > rhs.reclaimableBytes
        case .name: lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        case .date: (lhs.lastModified ?? .distantPast) < (rhs.lastModified ?? .distantPast)
        case .risk: (lhs.risk, rhs.reclaimableBytes) < (rhs.risk, lhs.reclaimableBytes)
        }
    }
}
