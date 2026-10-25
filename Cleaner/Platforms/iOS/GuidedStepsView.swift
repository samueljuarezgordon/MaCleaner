#if os(iOS)
import SwiftUI
import UIKit

/// Un paso de una guía: icono animado, título y explicación.
struct GuideStep: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
}

/// Guía paso a paso a pantalla completa, con avance por páginas y símbolos animados.
struct GuidedStepsView: View {
    let title: LocalizedStringResource
    let tint: Color
    let steps: [GuideStep]
    /// Advertencias que se muestran antes del primer paso (opcional).
    var warnings: [LocalizedStringResource] = []

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $index) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { position, step in
                        StepPage(step: step, number: position + 1, total: steps.count, tint: tint, isCurrent: position == index)
                            .tag(position)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                if index == 0, !warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                            Label { Text(warning) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: .rect(cornerRadius: 14))
                    .padding(.horizontal)
                }

                HStack {
                    Button("Anterior") { withAnimation { index -= 1 } }
                        .disabled(index == 0)
                    Spacer()
                    Button("Abrir Ajustes", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Spacer()
                    if index < steps.count - 1 {
                        Button("Siguiente") { withAnimation { index += 1 } }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button("Hecho") { dismiss() }
                            .buttonStyle(.glassProminent)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }
}

private struct StepPage: View {
    let step: GuideStep
    let number: Int
    let total: Int
    let tint: Color
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: step.systemImage)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(tint.gradient)
                .symbolEffect(.bounce, value: isCurrent)
                .frame(height: 90)
                .accessibilityHidden(true)
            Text("Paso \(number) de \(total)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(step.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(step.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
        .padding(32)
    }
}

// MARK: - Guías

enum Guides {
    /// Desinstalar una app pesada conservando sus datos (Offload).
    static let offload: [GuideStep] = [
        GuideStep(systemImage: "gearshape.fill", title: "Abre Ajustes",
                  detail: "Ve a Ajustes › General › Almacenamiento del iPhone (o del iPad). Espera unos segundos a que calcule el uso."),
        GuideStep(systemImage: "list.bullet.rectangle.fill", title: "Elige una app pesada",
                  detail: "La lista está ordenada por tamaño. Fíjate en «Último uso»: las que no usas desde hace meses son las mejores candidatas."),
        GuideStep(systemImage: "icloud.and.arrow.down.fill", title: "Pulsa «Desinstalar app»",
                  detail: "Se borra la app pero se conservan sus documentos y datos. Su icono sigue en la pantalla de inicio con una nube."),
        GuideStep(systemImage: "arrow.down.app.fill", title: "Recupérala cuando quieras",
                  detail: "Toca el icono y se vuelve a descargar con todos tus datos. Si quieres que iOS lo haga solo, activa «Desinstalar apps sin usar» en esa misma pantalla."),
    ]
}
#endif
