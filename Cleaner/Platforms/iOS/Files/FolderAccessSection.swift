#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers

/// Lista de carpetas que MaCleaner puede analizar, con el selector para añadir más.
struct FolderAccessSection: View {
    @State private var model = FolderAccessModel()
    @State private var isPicking = false

    var body: some View {
        Section {
            if model.folders.isEmpty {
                Text("Elige las carpetas que quieres analizar: «En mi iPhone», Descargas o iCloud Drive. MaCleaner solo verá las que elijas.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.folders, id: \.self) { folder in
                Label(folder.lastPathComponent, systemImage: folder.path.contains("Mobile Documents") ? "icloud" : "folder")
                    .swipeActions {
                        Button("Quitar", role: .destructive) { model.remove(folder) }
                    }
                    .contextMenu {
                        Button("Dejar de analizar", systemImage: "minus.circle", role: .destructive) { model.remove(folder) }
                    }
            }
            Button("Añadir carpeta…", systemImage: "folder.badge.plus") { isPicking = true }
        } header: {
            Text("Carpetas analizadas")
        } footer: {
            Text("Consejo: elige la carpeta raíz de iCloud Drive para encontrar copias locales que puedes liberar sin borrar nada de iCloud.")
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            model.add(result)
        }
        .alert("No se pudo añadir la carpeta", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// Tarjeta de la pantalla de inicio que invita a elegir carpetas si aún no hay ninguna.
struct FolderAccessPrompt: View {
    @State private var model = FolderAccessModel()
    @State private var isPicking = false

    var body: some View {
        if model.folders.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Analiza también tus archivos")
                        .font(.headline)
                    Text("Elige carpetas de Archivos (En mi iPhone, Descargas, iCloud Drive) para encontrar archivos grandes, comprimidos y copias de iCloud Drive que puedes liberar sin borrarlas de iCloud.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Elegir carpetas…") { isPicking = true }
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: .rect(cornerRadius: 16))
            .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
                model.add(result)
            }
        }
    }
}
#endif
