import Foundation
import NotePadCore

extension AppState {
    /// Keeps a copy of the text just saved. History is a safety net, so a failure here never blocks the save.
    func recordVersion(of doc: TextDocument) {
        guard let history, let url = doc.fileURL else { return }
        do {
            try history.record(doc.text, for: url)
        } catch {
            showNotice("Version history could not be updated. \(error.localizedDescription)")
        }
    }

    /// The saved versions of the active tab's file, newest first.
    func versionsOfActiveFile() throws -> [SavedVersion] {
        guard let history, let url = activeDocument?.fileURL else { return [] }
        return try history.versions(for: url)
    }

    func text(of version: SavedVersion) throws -> String {
        guard let history, let url = activeDocument?.fileURL else { throw VersionStoreError.missingVersion(version.id) }
        return try history.text(of: version, for: url)
    }

    /// Puts a saved version's text into the active tab as one undoable edit. The file changes only when the user saves.
    func restore(_ version: SavedVersion) throws {
        guard let doc = activeDocument, let editor = activeEditor else { return }
        guard !doc.isReadOnly else {
            showNotice("This file is read-only.")
            return
        }
        editor.replaceWholeText(try text(of: version))
        editor.focus()
        let date = version.date.formatted(date: .abbreviated, time: .shortened)
        showNotice("Restored the version from \(date). Save to keep it.")
    }
}
