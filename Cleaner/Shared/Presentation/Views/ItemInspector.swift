import SwiftUI

/// Panel lateral que explica a fondo un elemento: qué es, por qué tiene ese riesgo, qué
/// pasa si se borra y cómo se eliminará.
struct ItemInspector: View {
    let viewModel: CleanerViewModel
    let module: CleaningModule
    let items: [ScanItem]

    var body: some View {
        ScrollView {
            switch items.count {
            case 0: ModuleGuide(module: module)
            case 1: ItemDetails(viewModel: viewModel, item: items[0])
            default: MultipleSelectionSummary(viewModel: viewModel, items: items)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

/// Resumen cuando hay varios elementos resaltados en la lista.
private struct MultipleSelectionSummary: View {
    let viewModel: CleanerViewModel
    let items: [ScanItem]

    var body: some View {
        let bytes = items.reduce(0) { $0 + $1.reclaimableBytes }
        let included = viewModel.selectionState(of: items)
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(items.count) elementos")
                    .font(.title3.bold())
                if bytes > 0 {
                    Text(bytes.byteString)
                        .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(RiskLevel.allCases) { risk in
                    let count = items.count { $0.risk == risk }
                    if count > 0 {
                        HStack {
                            RiskBadge(risk: risk)
                            Spacer()
                            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Button(included == .all ? "Quitar todos de la limpieza" : "Incluir todos en la limpieza",
                       systemImage: included == .all ? "minus.circle" : "checkmark.circle") {
                    viewModel.setSelected(included != .all, for: items)
                }
                #if os(macOS)
                Button("Mostrar en el Finder", systemImage: "folder") {
                    PlatformActions.revealInFinder(items)
                }
                #endif
                Button("Ignorar siempre", systemImage: "eye.slash") {
                    viewModel.ignore(items)
                }
            }
            .buttonStyle(.glass)
            Text("Consejo: haz doble clic en un elemento para incluirlo o quitarlo, y pulsa la barra espaciadora para verlo con Vista rápida.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct ItemDetails: View {
    let viewModel: CleanerViewModel
    let item: ScanItem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                CategoryIcon(category: item.category, tint: item.risk.color, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.title3.bold())
                        .textSelection(.enabled)
                    Text(item.category.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if item.category.measuresSpace {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.reclaimableBytes.byteString)
                    .font(.system(.largeTitle, design: .rounded).bold().monospacedDigit())
                Text("se liberarán al limpiarlo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.allocatedBytes > item.reclaimableBytes {
                    Text("Ocupa \(item.allocatedBytes.byteString), pero parte de sus datos son clones APFS compartidos con otros archivos y no se liberarán.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            }

            VStack(alignment: .leading, spacing: 8) {
                RiskBadge(risk: item.risk, isProminent: true)
                Text(item.risk.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(item.risk.color.opacity(0.08), in: .rect(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 14) {
                ExplanationRow(title: "Por qué este riesgo", systemImage: item.risk.systemImage, text: Text(item.reason), tint: item.risk.color)
                ExplanationRow(title: "Qué es", systemImage: "questionmark.circle.fill", text: Text(item.category.explanation), tint: .blue)
                ExplanationRow(title: item.category.measuresSpace ? "Si lo borras" : "Si lo desactivas", systemImage: "arrow.uturn.backward.circle.fill", text: Text(item.category.consequence), tint: .orange)
                ExplanationRow(
                    title: item.category.measuresSpace ? "Cómo se elimina" : "Cómo se desactiva",
                    systemImage: item.removal.isRecoverable ? "trash.circle.fill" : "xmark.bin.circle.fill",
                    text: Text(item.removal.summary),
                    tint: item.removal.isRecoverable ? .green : .red
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Ubicación") {
                    Text(item.location)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                if let date = item.lastModified {
                    LabeledContent("Última modificación", value: date.formatted(.relative(presentation: .named)))
                }
            }
            .font(.callout)

            Toggle("Incluir en la limpieza", isOn: Binding(
                get: { viewModel.isSelected(item) },
                set: { viewModel.setSelected($0, for: item) }
            ))
            .toggleStyle(.switch)

            HStack {
                #if os(macOS)
                if PlatformActions.isLocalFile(item) {
                    Button("Mostrar en el Finder", systemImage: "folder") {
                        PlatformActions.revealInFinder([item])
                    }
                }
                #endif
                Button("Ignorar siempre", systemImage: "eye.slash") {
                    viewModel.ignore([item])
                }
                .help("No volver a mostrar este elemento. Puedes deshacerlo en Ajustes.")
            }
            .buttonStyle(.glass)
        }
        .padding(20)
    }
}

/// Lo que se muestra cuando no hay ningún elemento seleccionado.
private struct ModuleGuide: View {
    let module: CleaningModule

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ModuleIcon(module: module, size: 44)
            Text("Selecciona un elemento para ver qué es, por qué tiene ese riesgo y qué pasará si lo borras.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(module.categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Label {
                        Text(category.title).font(.headline)
                    } icon: {
                        Image(systemName: category.systemImage)
                    }
                    Text(category.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("\(category.measuresSpace ? String(localized: "Si lo borras") : String(localized: "Si lo desactivas")): \(String(localized: category.consequence))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }
}
