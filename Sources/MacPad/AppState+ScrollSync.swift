import Foundation
import MacPadCore

extension AppState {
    /// The editor now shows `topLine` at the top. The preview follows, unless the preview caused the scroll.
    func editorScrolled(_ doc: TextDocument, topLine: Int) {
        guard doc.id == activeID, !isFollowingPreview, topLine != previewLine else { return }
        previewLine = topLine
    }

    /// The user scrolled the preview to a new top line. The editor follows. The preview only reports
    /// user scrolls, so this never feeds back.
    func previewScrolled(_ line: Int) {
        guard let editor = activeEditor else { return }
        isFollowingPreview = true
        editor.scrollToLine(line)
        isFollowingPreview = false
    }

    /// Brings the preview to the position of the newly active tab.
    func syncPreviewToActiveTab() {
        previewLine = activeEditor?.topVisibleLine ?? 1
    }
}
