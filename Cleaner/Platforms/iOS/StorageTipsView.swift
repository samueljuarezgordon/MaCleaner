#if os(iOS)
import SwiftUI
import UIKit

/// Ahorros de espacio que iOS solo permite hacer desde Ajustes. Cada consejo explica qué se
/// borra, para qué servía y qué pasa después, igual que el mantenimiento de macOS.
struct StorageTipsView: View {
    private struct Tip: Identifiable {
        let id: String
        let title: LocalizedStringResource
        let systemImage: String
        let tint: Color
        let risk: RiskLevel
        let whatIsDeleted: LocalizedStringResource
        let purpose: LocalizedStringResource
        let afterwards: LocalizedStringResource
        let steps: LocalizedStringResource
    }

    private let tips: [Tip] = [
        Tip(
            id: "offload", title: "Descargar apps sin usar", systemImage: "icloud.and.arrow.down", tint: .blue, risk: .safe,
            whatIsDeleted: "La app, pero no sus documentos ni sus datos.",
            purpose: "Apps que no abres desde hace tiempo.",
            afterwards: "Su icono sigue en la pantalla de inicio. Al tocarlo se vuelve a descargar con todos tus datos intactos.",
            steps: "Ajustes › General › Almacenamiento del iPhone › Descargar apps sin usar."
        ),
        Tip(
            id: "recentlyDeleted", title: "Vaciar «Eliminados recientemente»", systemImage: "trash", tint: .red, risk: .moderate,
            whatIsDeleted: "Las fotos y vídeos que borraste en los últimos 30 días, incluidos los que borra MaCleaner.",
            purpose: "Te permite recuperar lo que borraste por error.",
            afterwards: "El espacio se libera al momento, pero ya no podrás recuperarlos.",
            steps: "Fotos › Colecciones › Eliminados recientemente › Seleccionar › Eliminar todo."
        ),
        Tip(
            id: "messages", title: "Conservar mensajes 1 año", systemImage: "message.fill", tint: .green, risk: .moderate,
            whatIsDeleted: "Mensajes y adjuntos de más de un año.",
            purpose: "El historial completo de tus conversaciones.",
            afterwards: "Los mensajes antiguos y sus fotos desaparecen de todos tus dispositivos con iCloud.",
            steps: "Ajustes › Apps › Mensajes › Conservar mensajes › 1 año. Revisa también «Revisar archivos adjuntos grandes» en Almacenamiento."
        ),
        Tip(
            id: "safari", title: "Borrar datos de Safari", systemImage: "safari.fill", tint: .cyan, risk: .moderate,
            whatIsDeleted: "Historial, cookies y caché de las webs.",
            purpose: "Que las webs carguen más rápido y recuerden tu sesión.",
            afterwards: "Tendrás que volver a iniciar sesión en las webs que uses.",
            steps: "Ajustes › Apps › Safari › Borrar historial y datos de sitios web."
        ),
        Tip(
            id: "streaming", title: "Descargas de música y vídeo", systemImage: "play.rectangle.on.rectangle.fill", tint: .pink, risk: .safe,
            whatIsDeleted: "Canciones, series y películas descargadas para ver sin conexión.",
            purpose: "Reproducirlas sin internet.",
            afterwards: "Siguen en tu biblioteca y se pueden volver a descargar cuando quieras.",
            steps: "En cada app (Música, TV, Spotify, Netflix…) › Descargas. En Música: Ajustes › Apps › Música › Optimizar almacenamiento."
        ),
        Tip(
            id: "optimizePhotos", title: "Optimizar el almacenamiento de Fotos", systemImage: "photo.on.rectangle", tint: .orange, risk: .safe,
            whatIsDeleted: "Los originales a máxima resolución guardados en el dispositivo.",
            purpose: "Ver tus fotos a máxima calidad sin conexión.",
            afterwards: "El iPhone guarda versiones más ligeras y descarga el original de iCloud cuando lo abres.",
            steps: "Ajustes › Apps › Fotos › Optimizar almacenamiento (requiere Fotos en iCloud)."
        ),
    ]

    var body: some View {
        List {
            Section {
                Text("iOS no permite que ninguna app borre datos de otras apps ni desinstale apps. Estos ahorros solo se pueden hacer desde Ajustes; aquí tienes qué hace cada uno y dónde está.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(tips) { tip in
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: tip.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(tip.tint.gradient, in: .rect(cornerRadius: 10))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tip.title).font(.headline)
                                RiskBadge(risk: tip.risk)
                            }
                        }
                        ExplanationRow(title: "Qué se borra", systemImage: "trash.circle.fill", text: Text(tip.whatIsDeleted), tint: .red)
                        ExplanationRow(title: "Para qué servía", systemImage: "questionmark.circle.fill", text: Text(tip.purpose), tint: .blue)
                        ExplanationRow(title: "Qué pasa después", systemImage: "arrow.uturn.backward.circle.fill", text: Text(tip.afterwards), tint: .orange)
                        ExplanationRow(title: "Dónde", systemImage: "gearshape.circle.fill", text: Text(tip.steps), tint: .gray)
                    }
                    .padding(.vertical, 6)
                }
            }
            Section {
                Button("Abrir Ajustes", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .navigationTitle("Consejos de espacio")
    }
}
#endif
