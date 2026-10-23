import SwiftUI

/// Cápsula de color con el nivel de riesgo.
struct RiskBadge: View {
    let risk: RiskLevel
    var isProminent = false

    var body: some View {
        Label {
            Text(risk.title)
        } icon: {
            Image(systemName: risk.systemImage)
        }
        .font(isProminent ? .callout.weight(.semibold) : .caption.weight(.semibold))
        .padding(.horizontal, isProminent ? 12 : 8)
        .padding(.vertical, isProminent ? 6 : 3)
        .foregroundStyle(risk.color)
        .background(risk.color.opacity(0.15), in: .capsule)
        .accessibilityLabel(Text("Riesgo: \(risk.title)"))
    }
}

/// Icono de módulo sobre un cuadrado redondeado con degradado.
struct ModuleIcon: View {
    let module: CleaningModule
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: module.systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(module.gradient, in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

/// Barra horizontal apilada con los bytes de cada nivel de riesgo.
struct RiskBar: View {
    let stats: CleanerViewModel.ModuleStats
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(RiskLevel.allCases) { risk in
                    let bytes = stats.bytes(for: risk)
                    if bytes > 0, stats.totalBytes > 0 {
                        risk.color
                            .frame(width: max(height, proxy.size.width * Double(bytes) / Double(stats.totalBytes)))
                    }
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text(RiskBar.accessibilityText(for: stats)))
    }

    private static func accessibilityText(for stats: CleanerViewModel.ModuleStats) -> String {
        RiskLevel.allCases
            .filter { stats.bytes(for: $0) > 0 }
            .map { "\(String(localized: $0.title)): \(stats.bytes(for: $0).byteString)" }
            .joined(separator: ", ")
    }
}

/// Leyenda de colores de riesgo.
struct RiskLegend: View {
    let stats: CleanerViewModel.ModuleStats
    /// Oculta los niveles sin bytes.
    var hidesEmpty = false

    var body: some View {
        HStack(spacing: 16) {
            ForEach(RiskLevel.allCases.filter { !hidesEmpty || stats.bytes(for: $0) > 0 }) { risk in
                HStack(spacing: 6) {
                    Circle().fill(risk.color).frame(width: 8, height: 8)
                    Text(risk.title)
                    Text(stats.bytes(for: risk).byteString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }
}

/// Uso del disco con anillo y desglose.
struct DiskUsageCard: View {
    let usage: DiskUsage

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: usage.usedFraction)
                    .stroke(
                        usage.usedFraction > 0.9 ? AnyShapeStyle(Color.red) : AnyShapeStyle(AppTheme.scanGradient),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text(usage.usedFraction, format: .percent.precision(.fractionLength(0)))
                    .font(.callout.weight(.bold).monospacedDigit())
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Disco de arranque")
                    .font(.headline)
                Text("\(usage.availableBytes.byteString) libres de \(usage.totalBytes.byteString)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if usage.purgeableBytes > 0 {
                    Text("+ \(usage.purgeableBytes.byteString) purgables por macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// Anillo animado que se muestra durante el escaneo y la limpieza.
struct ScanRing: View {
    let title: String
    let value: String
    let subtitle: String

    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 14)
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(AppTheme.scanGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(rotation))
            VStack(spacing: 6) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 240, height: 240)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

/// Casilla de selección de tres estados para categorías completas.
struct SelectionCheckbox: View {
    let state: CleanerViewModel.SelectionState
    let action: (Bool) -> Void

    var body: some View {
        Button {
            action(state != .all)
        } label: {
            Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(state == .none ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(state == .all ? "Desmarcar todo" : "Marcar todo")
    }

    private var symbol: String {
        switch state {
        case .all: "checkmark.circle.fill"
        case .some: "minus.circle.fill"
        case .none: "circle"
        }
    }
}

/// Bloque de texto con título e icono, para explicaciones en el inspector y las tarjetas.
struct ExplanationRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    let text: Text
    var tint: Color = .secondary

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                text
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

/// Icono de categoría coloreado según el riesgo de un elemento.
struct CategoryIcon: View {
    let category: CleaningCategory
    var tint: Color = .accentColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}
