import SwiftUI

/// Colores y degradados de la app.
enum AppTheme {
    /// Fondo de la pantalla principal: violeta profundo a magenta.
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.13, green: 0.07, blue: 0.30),
            Color(red: 0.32, green: 0.10, blue: 0.45),
            Color(red: 0.55, green: 0.13, blue: 0.47),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let scanGradient = AngularGradient(
        colors: [.cyan, .blue, .purple, .pink, .cyan],
        center: .center
    )
}

extension RiskLevel {
    var color: Color {
        switch self {
        case .safe: .green
        case .moderate: .orange
        case .high: .red
        }
    }
}

extension CleaningModule {
    var gradient: LinearGradient {
        let colors: [Color] = switch self {
        case .systemJunk: [.pink, .purple]
        case .developer: [.blue, .indigo]
        case .applications: [.cyan, .blue]
        case .startup: [.yellow, .red]
        case .downloads: [.teal, .blue]
        case .leftovers: [.orange, .pink]
        case .largeFiles: [.yellow, .orange]
        case .trash: [.gray, Color(white: 0.35)]
        case .photos: [.green, .teal]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Int64 {
    /// "4,5 GB"
    var byteString: String {
        formatted(.byteCount(style: .file))
    }
}
