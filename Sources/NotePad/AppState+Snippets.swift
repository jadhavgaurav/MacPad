import Foundation
import NotePadCore

extension AppState {
    /// Inserts a snippet at the caret, replacing any selection, and expands its placeholders.
    func insertSnippet(_ snippet: Snippet) {
        guard let doc = activeDocument, let editor = activeEditor else { return }
        guard !doc.isReadOnly else {
            showNotice("This file is read-only.")
            return
        }
        let expansion = SnippetExpander.expand(snippet.body, at: Date())
        editor.insertText(expansion.text, caretOffset: expansion.caretOffset)
    }

    /// Saves the current selection as a named snippet for the Snippets menu.
    func saveSelectionAsSnippet() {
        guard let editor = activeEditor else { return }
        let body = editor.selectedText
        guard !body.isEmpty else {
            showNotice("Select some text to save as a snippet.")
            return
        }
        guard let name = Dialogs.askSnippetName(suggested: Self.suggestedSnippetName(for: body)) else { return }
        do {
            try snippets.add(name: name, body: body)
        } catch {
            Dialogs.showError(error)
        }
    }

    func deleteSnippet(_ snippet: Snippet) {
        guard Dialogs.confirmDeleteSnippet(snippet.name) else { return }
        do {
            try snippets.remove(id: snippet.id)
        } catch {
            Dialogs.showError(error)
        }
    }

    /// The first line of the text, trimmed and shortened, so the name field starts with something useful.
    private static func suggestedSnippetName(for body: String) -> String {
        let firstLine = body.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return firstLine.isEmpty ? "Snippet" : String(firstLine.prefix(40))
    }
}
