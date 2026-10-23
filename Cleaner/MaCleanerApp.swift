import SwiftUI

@main struct MaCleanerApp: App {
    @State private var viewModel = CleanerViewModel()

    init() {
        #if os(iOS)
        // Si la app se cerró en mitad de una purga de espacio, se libera la reserva.
        PurgeableSpaceReclaimer.removeLeftoverReservation()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 780)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            CleanerCommands(viewModel: viewModel)
        }

        #if os(macOS)
        Settings {
            SettingsView(viewModel: viewModel)
        }
        #endif
    }
}

/// Menú «Limpieza» con atajos de teclado para las acciones principales.
struct CleanerCommands: Commands {
    let viewModel: CleanerViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandMenu("Limpieza") {
            Button(viewModel.hasResults ? "Volver a analizar" : "Analizar", action: viewModel.startScan)
                .keyboardShortcut("r")
                .disabled(viewModel.phase == .scanning || viewModel.phase == .cleaning)
            Button("Detener análisis", action: viewModel.cancel)
                .keyboardShortcut(".")
                .disabled(viewModel.phase != .scanning)

            Divider()

            Button("Seleccionar solo lo seguro") { viewModel.select(upTo: .safe) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Seleccionar lo seguro y lo que hay que revisar") { viewModel.select(upTo: .moderate) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("No seleccionar nada") { viewModel.select(upTo: nil) }
                .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button("Revisar y limpiar…") { viewModel.isReviewingClean = true }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(viewModel.phase != .results || viewModel.selection.isEmpty)
        }
    }
}
