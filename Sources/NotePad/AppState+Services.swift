import Foundation
import NotePadCore

extension AppState {
    /// Opens text sent through the Services menu in a new unsaved tab.
    func openServiceText(_ text: String) {
        add(TextDocument(text: text, isDirty: true))
    }
}
