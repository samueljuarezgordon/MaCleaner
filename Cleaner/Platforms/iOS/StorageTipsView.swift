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
            whatIsDeleted: "Los originales a máxima resolución guardados en el dispositivo. Siguen en iCloud: no se borra ninguna foto.",
            purpose: "Ver tus fotos a máxima calidad sin conexión.",
            afterwards: "El dispositivo guarda versiones más ligeras y descarga el original de iCloud cuando lo abres. Con esto activado, «Liberar espacio purgable» puede vaciar la caché de Fotos en iCloud.",
            steps: "Ajustes › Apps › Fotos › Optimizar almacenamiento (requiere Fotos en iCloud)."
        ),
    ]

    var body: some View {
        List {
            PurgeableSpaceSection()

            Section {
                Text("iOS no permite que ninguna app borre datos de otras apps ni desinstale apps. Estos ahorros solo se pueden hacer desde Ajustes; aquí tienes qué hace cada uno y dónde está.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Desde Ajustes")
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
        .navigationTitle("Mantenimiento")
    }
}

// MARK: - Espacio purgable

/// Estado de la purga de espacio («Datos del sistema»).
@MainActor
@Observable
final class PurgeableSpaceModel {
    enum Phase: Equatable {
        case idle
        case running
        case finished(freedBytes: Int64)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var usage = DiskUsage.current()
    private(set) var progress: PurgeableSpaceReclaimer.Progress?
    private var task: Task<Void, Never>?

    /// Lo que iOS considera purgable ahora mismo (cachés, temporales, originales optimizables).
    var purgeableBytes: Int64 { usage?.purgeableBytes ?? 0 }

    func refresh() {
        guard phase != .running else { return }
        usage = DiskUsage.current()
    }

    func start() {
        guard phase != .running else { return }
        let before = PurgeableSpaceReclaimer.available()
        phase = .running
        progress = nil
        task = Task {
            do {
                try await PurgeableSpaceReclaimer.run { progress in
                    Task { @MainActor in self.progress = progress }
                }
                // Se deja un momento para que iOS termine de contabilizar lo liberado.
                try? await Task.sleep(for: .seconds(1))
                let after = PurgeableSpaceReclaimer.available()
                phase = .finished(freedBytes: max(0, after - before))
            } catch {
                phase = .failed(error.localizedDescription)
            }
            usage = DiskUsage.current()
        }
    }

    /// Detiene la purga y libera la reserva al instante.
    func cancel() {
        task?.cancel()
    }
}

/// Tarjeta para liberar el espacio purgable, con la misma explicación que el resto de acciones.
private struct PurgeableSpaceSection: View {
    @State private var model = PurgeableSpaceModel()
    @State private var isConfirming = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "internaldrive.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.indigo.gradient, in: .rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Liberar espacio purgable").font(.headline)
                        Text("Datos del sistema, cachés y caché de Fotos en iCloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        RiskBadge(risk: .safe)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.purgeableBytes.byteString)
                            .font(.title3.bold().monospacedDigit())
                        Text("purgable según iOS")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ExplanationRow(title: "Qué se borra", systemImage: "trash.circle.fill", text: Text("Lo que iOS marca como purgable: cachés de otras apps, archivos temporales, cachés de streaming y, si tienes «Optimizar almacenamiento» en Fotos, los originales que ya están en iCloud."), tint: .red)
                ExplanationRow(title: "Para qué servía", systemImage: "questionmark.circle.fill", text: Text("Que las apps abran más rápido y que las fotos se vean a máxima calidad sin conexión."), tint: .blue)
                ExplanationRow(title: "Qué pasa después", systemImage: "arrow.uturn.backward.circle.fill", text: Text("No se borra ninguna foto ni documento: tus fotos siguen en iCloud. Las apps reconstruyen sus cachés y los originales se vuelven a descargar al abrirlos."), tint: .orange)
                ExplanationRow(title: "Cómo funciona", systemImage: "gearshape.2.fill", text: Text("Ninguna app puede borrar cachés ajenas en iOS. MaCleaner reserva durante unos segundos el espacio libre (sin escribir datos) para que iOS vea el almacenamiento casi lleno y purgue él mismo. Siempre deja \(PurgeableSpaceReclaimer.safetyFloor.byteString) libres y lo libera todo al terminar."), tint: .gray)

                switch model.phase {
                case .running:
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView()
                        if let progress = model.progress {
                            Text("Reservado \(progress.reservedBytes.byteString) · iOS ha liberado ≈ \(progress.purgedBytes.byteString)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text("Mantén MaCleaner abierta. Tarda hasta un minuto.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Detener", role: .cancel, action: model.cancel)
                    }
                case .finished(let freed):
                    Label(freed > 0 ? "Liberados \(freed.byteString)" : "iOS no tenía nada más que purgar ahora mismo", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                case .idle:
                    EmptyView()
                }

                if model.phase != .running {
                    Button {
                        isConfirming = true
                    } label: {
                        Text("Liberar espacio purgable")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Desde MaCleaner")
        } footer: {
            Text("iOS decide qué purgar. Si apenas hay espacio purgable, el resultado será pequeño.")
        }
        .confirmationDialog("¿Liberar espacio purgable?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Liberar espacio") { model.start() }
        } message: {
            Text("Durante hasta un minuto el almacenamiento aparecerá casi lleno. No hagas fotos ni descargues nada mientras tanto. No se borra ninguna foto ni documento.")
        }
        .onChange(of: scenePhase) { _, phase in
            // Si la app pasa a segundo plano, se libera la reserva al momento.
            if phase != .active { model.cancel() }
            if phase == .active { model.refresh() }
        }
        .onAppear(perform: model.refresh)
    }
}
#endif
