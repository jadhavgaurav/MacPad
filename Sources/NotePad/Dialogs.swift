import AppKit
import NotePadCore

@MainActor
enum Dialogs {
    enum CloseChoice { case save, discard, cancel }

    static func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    static func confirmClose(_ document: TextDocument) -> CloseChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \(document.title)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    /// Asks for a snippet name. Returns nil when cancelled or left blank.
    static func askSnippetName(suggested: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Save Snippet"
        alert.informativeText = "The snippet appears in the Snippets menu."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: suggested)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        field.setAccessibilityLabel("Snippet name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func confirmDeleteSnippet(_ name: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \u{201C}\(name)\u{201D}?"
        alert.informativeText = "The snippet is removed from the Snippets menu. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    enum CloseManyChoice { case saveAll, discardAll, cancel }

    /// One question for several tabs with unsaved changes.
    static func confirmCloseMany(_ titles: [String]) -> CloseManyChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = titles.count == 1
            ? "Do you want to save changes to \(titles[0])?"
            : "Do you want to save changes to \(titles.count) tabs?"
        alert.informativeText = "Unsaved changes in: " + titles.joined(separator: ", ") + ". Changes you don't save will be lost."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .saveAll
        case .alertSecondButtonReturn: return .discardAll
        default: return .cancel
        }
    }

    /// Asks which encoding to try when a file can't be decoded automatically.
    static func chooseEncoding(for url: URL, message: String) -> TextEncoding? {
        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) can't be opened as text."
        alert.informativeText = message
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26))
        TextEncoding.allCases.forEach { picker.addItem(withTitle: $0.label) }
        alert.accessoryView = picker
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return TextEncoding.allCases[picker.indexOfSelectedItem]
    }
}
