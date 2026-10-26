import SwiftUI

/// Barra inferior con el resumen de la selección. La limpieza siempre pasa por una hoja de
/// revisión.
struct CleanBar: View {
    let viewModel: CleanerViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.selectedStats.itemCount) elementos seleccionados")
                    .font(.headline)
                RiskLegend(stats: viewModel.selectedStats, hidesEmpty: true)
            }
            Spacer()
            Button {
                viewModel.isReviewingClean = true
            } label: {
                Text(viewModel.selectedStats.totalBytes > 0
                     ? "Revisar y limpiar \(viewModel.selectedStats.totalBytes.byteString)"
                     : "Revisar y aplicar")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.delete, modifiers: .command)
            .help("Revisar y limpiar (⌘⌫)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 22))
        .padding(16)
    }
}

/// Última comprobación antes de borrar: desglose por riesgo, lo que es recuperable y los
/// elementos de riesgo alto incluidos.
struct CleanReviewSheet: View {
    let viewModel: CleanerViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.skipTrashKey) private var permanently = false

    var body: some View {
        let breakdown = viewModel.removalBreakdown(permanently: permanently)
        let stats = viewModel.selectedStats

        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stats.totalBytes.byteString)
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        Text("\(stats.itemCount) elementos")
                            .foregroundStyle(.secondary)
                        RiskBar(stats: stats, height: 10)
                    }
                    .padding(.vertical, 4)
                }

                if startupCount > 0 {
                    Section {
                        Label("\(startupCount) procesos de inicio se detendrán y dejarán de arrancar con el Mac", systemImage: "bolt.slash.fill")
                    }
                }

                if photoCount > 0 {
                    Section {
                        Label("\(photoCount) fotos y vídeos se borrarán de tu fototeca", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("Van a «Eliminados recientemente» durante 30 días. Si usas Fotos en iCloud, se borran también de iCloud y de tus otros dispositivos. iOS te pedirá confirmación antes de borrarlas.")
                    }
                }

                Section("Por nivel de riesgo") {
                    ForEach(RiskLevel.allCases) { risk in
                        LabeledContent {
                            Text(stats.bytes(for: risk).byteString).monospacedDigit()
                        } label: {
                            RiskBadge(risk: risk)
                        }
                    }
                }

                Section {
                    LabeledContent("Recuperable (Papelera)") {
                        Text(breakdown.recoverableBytes.byteString).monospacedDigit()
                    }
                    LabeledContent("Se borra definitivamente") {
                        Text(breakdown.permanentBytes.byteString).monospacedDigit()
                    }
                    Toggle("No usar la Papelera", isOn: $permanently)
                } header: {
                    Text("Cómo se eliminará")
                } footer: {
                    Text("Las cachés, registros y artefactos que se regeneran solos se borran directamente. Los instaladores, restos de apps y archivos personales van a la Papelera salvo que actives esta opción.")
                }

                if !breakdown.highRiskItems.isEmpty {
                    Section {
                        ForEach(breakdown.highRiskItems.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(item.displayName).lineLimit(1)
                                    Spacer()
                                    Text(item.reclaimableBytes.byteString)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if breakdown.highRiskItems.count > 8 {
                            Text("Y \(breakdown.highRiskItems.count - 8) más")
                                .foregroundStyle(.secondary)
                        }
                        Button("Quitar los de riesgo alto", role: .destructive) {
                            viewModel.setSelected(false, for: breakdown.highRiskItems)
                        }
                    } header: {
                        Label("Incluye elementos de riesgo alto", systemImage: RiskLevel.high.systemImage)
                            .foregroundStyle(RiskLevel.high.color)
                    } footer: {
                        Text("Podrían ser tu única copia. Asegúrate de que no los necesitas.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Revisar antes de limpiar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(stats.totalBytes > 0 ? "Limpiar \(stats.totalBytes.byteString)" : "Aplicar", role: .destructive) {
                        viewModel.cleanSelection(permanently: permanently)
                        dismiss()
                    }
                    .disabled(stats.itemCount == 0)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 520)
        #endif
    }

    private var photoCount: Int {
        viewModel.selectedItems().count { $0.removal == .photoLibrary }
    }

    private var startupCount: Int {
        viewModel.selectedItems().count { !$0.category.measuresSpace }
    }
}
