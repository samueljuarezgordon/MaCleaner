import Foundation

/// Preferencias de la app guardadas en `UserDefaults`.
nonisolated enum Preferences {
    static let exclusionsKey = "excludedItemIDs"
    static let defaultSelectionKey = "defaultSelection"
    static let skipTrashKey = "skipTrashByDefault"
    static let sortOrderKey = "itemSortOrder"

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
