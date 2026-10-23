import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Acciones que dependen de la plataforma (Finder, portapapeles, Ajustes del sistema).
enum PlatformActions {
    /// `true` si el elemento es un archivo local que se puede mostrar o previsualizar.
    static func isLocalFile(_ item: ScanItem) -> Bool {
        #if os(macOS)
        item.id.hasPrefix("/") && FileManager.default.fileExists(atPath: item.id)
        #else
        false
        #endif
    }

    static func revealInFinder(_ items: [ScanItem]) {
        #if os(macOS)
        let urls = items.filter(isLocalFile).map { URL(fileURLWithPath: $0.id) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        #endif
    }

    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    #if os(macOS)
    static func openTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
    }

    /// Ajustes del Sistema › General › Ítems de inicio de sesión.
    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}
