import SwiftUI

/// Pantallas de la barra lateral.
enum SidebarDestination: Hashable {
    case overview
    case module(CleaningModule)
    #if os(macOS)
    case maintenance
    #else
    case tips
    case settings
    #endif
}

struct ContentView: View {
    @Bindable var viewModel: CleanerViewModel
    @State private var destination: SidebarDestination? = .overview

    /// La barra de limpieza no tiene sentido en la pantalla de mantenimiento.
    private var showsCleanBar: Bool {
        #if os(macOS)
        destination != .maintenance
        #else
        destination != .tips && destination != .settings
        #endif
    }

    var body: some View {
        NavigationSplitView {
            Sidebar(viewModel: viewModel, destination: $destination)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            NavigationStack {
                switch destination ?? .overview {
                case .overview:
                    OverviewView(viewModel: viewModel, destination: $destination)
                case .module(let module):
                    ModuleDetailView(viewModel: viewModel, module: module)
                        .id(module)
                #if os(macOS)
                case .maintenance:
                    MaintenanceView()
                #else
                case .tips:
                    StorageTipsView()
                case .settings:
                    SettingsView(viewModel: viewModel)
                #endif
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.phase == .results, !viewModel.selection.isEmpty, showsCleanBar {
                    CleanBar(viewModel: viewModel)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth, value: viewModel.selection.isEmpty)
            .animation(.smooth, value: viewModel.phase)
        }
        .sheet(isPresented: $viewModel.isReviewingClean) {
            CleanReviewSheet(viewModel: viewModel)
        }
        .alert(
            "No se pudo completar la operación",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Barra lateral

private struct Sidebar: View {
    let viewModel: CleanerViewModel
    @Binding var destination: SidebarDestination?

    var body: some View {
        List(selection: $destination) {
            NavigationLink(value: SidebarDestination.overview) {
                Label("Análisis inteligente", systemImage: "sparkles")
            }

            Section("Limpieza") {
                ForEach(viewModel.modules) { module in
                    NavigationLink(value: SidebarDestination.module(module)) {
                        SidebarModuleRow(module: module, stats: viewModel.stats(for: module), phase: viewModel.phase)
                            // Los módulos que no se analizan se atenúan.
                            .opacity(viewModel.scanSelectionState(of: module) == .none ? 0.45 : 1)
                    }
                }
            }

            Section("Herramientas") {
                #if os(macOS)
                NavigationLink(value: SidebarDestination.maintenance) {
                    Label("Mantenimiento y permisos", systemImage: "wrench.and.screwdriver.fill")
                }
                #else
                NavigationLink(value: SidebarDestination.tips) {
                    Label("Mantenimiento y consejos", systemImage: "wrench.and.screwdriver.fill")
                }
                NavigationLink(value: SidebarDestination.settings) {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
                #endif
            }
        }
        .navigationTitle("MaCleaner")
        .safeAreaInset(edge: .bottom) {
            if let usage = viewModel.diskUsage {
                SidebarDiskUsage(usage: usage)
                    .padding(10)
            }
        }
    }
}

private struct SidebarModuleRow: View {
    let module: CleaningModule
    let stats: CleanerViewModel.ModuleStats
    let phase: CleanerViewModel.Phase

    var body: some View {
        HStack(spacing: 10) {
            ModuleIcon(module: module, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                Text(module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !module.measuresSpace, stats.itemCount > 0 {
                Text("\(stats.itemCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if stats.totalBytes > 0 {
                Text(stats.totalBytes.byteString)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarDiskUsage: View {
    let usage: DiskUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Disco de arranque", systemImage: "internaldrive.fill")
                .font(.caption.weight(.semibold))
            ProgressView(value: usage.usedFraction)
                .tint(usage.usedFraction > 0.9 ? .red : .accentColor)
            Text("\(usage.availableBytes.byteString) libres de \(usage.totalBytes.byteString)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ContentView(viewModel: CleanerViewModel())
}
