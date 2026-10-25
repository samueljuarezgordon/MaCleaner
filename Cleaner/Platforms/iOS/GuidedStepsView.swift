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

    /// Truco del salto temporal para que iOS dé por caducadas cachés antiguas.
    static let timeJump: [GuideStep] = [
        GuideStep(systemImage: "airplane", title: "Activa el Modo Avión",
                  detail: "Desde el Centro de control. Así ninguna app ni servicio de iCloud se sincroniza con la fecha falsa."),
        GuideStep(systemImage: "clock.badge.xmark", title: "Desactiva la hora automática",
                  detail: "Ajustes › General › Fecha y hora › desactiva «Ajustar automáticamente». Si no te deja, desactiva antes Tiempo de uso o la restricción correspondiente."),
        GuideStep(systemImage: "calendar.badge.plus", title: "Adelanta la fecha un año",
                  detail: "Toca la fecha y avanza el año. No cambies nada más."),
        GuideStep(systemImage: "internaldrive.fill", title: "Abre Almacenamiento y espera",
                  detail: "Ve a Ajustes › General › Almacenamiento y espera uno o dos minutos con la pantalla encendida. iOS puede dar por caducadas cachés con fecha de expiración."),
        GuideStep(systemImage: "arrow.uturn.backward.circle.fill", title: "Vuelve a la fecha real",
                  detail: "Activa de nuevo «Ajustar automáticamente», desactiva el Modo Avión y reinicia el dispositivo. No te saltes este paso."),
    ]

    static let timeJumpWarnings: [LocalizedStringResource] = [
        "Es un truco no documentado por Apple: el resultado no está garantizado y a menudo es pequeño.",
        "Mientras la fecha es falsa pueden fallar iCloud, Apple Pay, el inicio de sesión con doble factor, las alarmas y las suscripciones. Vuelve siempre a la fecha automática.",
        "Prueba antes «Liberar espacio purgable»: es más seguro y suele liberar más.",
    ]
}
#endif
