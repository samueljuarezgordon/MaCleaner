#if os(iOS)
import Foundation
import Observation

/// Carpetas que el usuario ha permitido analizar (En mi iPhone, Descargas, iCloud Drive…).
///
/// El sandbox de iOS solo deja leer fuera del contenedor de la app las carpetas que el
/// usuario elige en el selector de archivos. El permiso se guarda como *bookmark* para que
/// siga valiendo tras cerrar la app.
nonisolated enum FolderAccessStore {
    private static let key = "grantedFolderBookmarks"

    /// Carpetas concedidas que todavía se pueden resolver.
    static func folders() -> [URL] {
        let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        var refreshed: [Data] = []
        var urls: [URL] = []
        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
                continue
            }
            urls.append(url)
            // Un bookmark caducado se regenera mientras aún se puede resolver.
            if isStale, let fresh = withAccess(to: url, { try? url.bookmarkData() }) {
                refreshed.append(fresh)
            } else {
                refreshed.append(data)
            }
        }
        if refreshed != bookmarks {
            UserDefaults.standard.set(refreshed, forKey: key)
        }
        return urls
    }

    /// Guarda el permiso para una carpeta elegida en el selector.
    static func add(_ url: URL) throws {
        let data = try withAccess(to: url) { try url.bookmarkData() }
        var bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        let existing = folders().map(\.standardizedFileURL)
        guard !existing.contains(url.standardizedFileURL) else { return }
        bookmarks.append(data)
        UserDefaults.standard.set(bookmarks, forKey: key)
    }

    static func remove(_ url: URL) {
        let bookmarks = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        let kept = bookmarks.filter { data in
            var isStale = false
            let resolved = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            return resolved?.standardizedFileURL != url.standardizedFileURL
        }
        UserDefaults.standard.set(kept, forKey: key)
    }

    /// Ejecuta `body` con el permiso de seguridad de la carpeta activo.
    static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Activa el permiso de todas las carpetas mientras dura `body` (para borrar archivos).
    static func withAccessToAll<T>(_ body: () async throws -> T) async rethrows -> T {
        let started = folders().filter { $0.startAccessingSecurityScopedResource() }
        defer { started.forEach { $0.stopAccessingSecurityScopedResource() } }
        return try await body()
    }
}

/// Estado observable de las carpetas concedidas, para la interfaz.
@MainActor
@Observable
final class FolderAccessModel {
    private(set) var folders: [URL] = FolderAccessStore.folders()
    var errorMessage: String?

    func add(_ result: Result<[URL], any Error>) {
        do {
            for url in try result.get() {
                try FolderAccessStore.add(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        folders = FolderAccessStore.folders()
    }

    func remove(_ url: URL) {
        FolderAccessStore.remove(url)
        folders = FolderAccessStore.folders()
    }
}
#endif
