import AppKit

extension AppState {
    /// Opens the system share menu for the active tab. A saved file shares its file; an unsaved tab shares its text.
    func shareActive() {
        guard let doc = activeDocument, let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView else { return }
        let items: [Any] = doc.fileURL.map { [$0 as Any] } ?? [doc.text as Any]
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1), of: view, preferredEdge: .minY)
    }
}
