import SwiftUI

/// Preferencias: qué se selecciona por defecto, cómo se borra y qué se ignora.
struct SettingsView: View {
    let viewModel: CleanerViewModel
    @AppStorage(Preferences.defaultSelectionKey) private var defaultSelection: Preferences.DefaultSelection = .safe
    @AppStorage(Preferences.skipTrashKey) private var skipTrash = false

    var body: some View {
        Form {
            #if os(iOS)
            FolderAccessSection()
            #endif

            Section {
                ForEach(viewModel.modules) { module in
                    DisclosureGroup {
                        ForEach(viewModel.supportedCategories(in: module)) { category in
                            Toggle(isOn: Binding(
                                get: { viewModel.isEnabled(category) },
                                set: { viewModel.setEnabled($0, for: [category]) }
                            )) {
                                Label {
                                    Text(category.title)
                                } icon: {
                                    Image(systemName: category.systemImage)
                                }
                            }
                        }
                    } label: {
                        Toggle(isOn: Binding(
                            get: { viewModel.scanSelectionState(of: module) != .none },
                            set: { viewModel.setEnabled($0, for: viewModel.supportedCategories(in: module)) }
                        )) {
                            Label {
                                Text(module.title)
                            } icon: {
                                Image(systemName: module.systemImage)
                            }
                        }
                    }
                }
            } header: {
                Text("Qué analizar")
            } footer: {
                Text("Lo que desactives no se analiza al pulsar «Analizar». Puedes analizar un módulo suelto desde su pantalla; el resto de resultados se conserva.")
            }

            Section {
                Picker("Seleccionar automáticamente", selection: $defaultSelection) {
                    ForEach(Preferences.DefaultSelection.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } header: {
                Text("Al terminar el análisis")
            } footer: {
                Text("Lo de riesgo alto nunca se selecciona automáticamente.")
            }

            Section {
                Toggle("No usar la Papelera", isOn: $skipTrash)
            } header: {
                Text("Limpieza")
            } footer: {
                Text("Si lo activas, lo que normalmente iría a la Papelera (instaladores, restos de apps, archivos personales) se borrará definitivamente. Puedes cambiarlo también en cada limpieza.")
            }

            Section {
                if viewModel.excludedIDs.isEmpty {
                    Text("No has ignorado nada. Usa «Ignorar siempre» en el menú contextual de un elemento para que no vuelva a aparecer.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.excludedIDs.sorted(), id: \.self) { id in
                        HStack {
                            Text(id)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Dejar de ignorar", systemImage: "xmark.circle.fill") {
                                viewModel.stopIgnoring(id)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Volverá a aparecer en el próximo análisis")
                        }
                    }
                    Button("Dejar de ignorar todo", role: .destructive, action: viewModel.clearExclusions)
                }
            } header: {
                Text("Elementos ignorados (\(viewModel.excludedIDs.count))")
            }

            Section("Privacidad") {
                Label("Todo el análisis se hace en tu dispositivo. MaCleaner no envía datos a ningún servidor.", systemImage: "hand.raised.fill")
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    LabeledContent("Versión", value: version)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }
}
