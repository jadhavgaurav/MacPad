import NotePadCore
import SwiftUI

/// "Changed on disk" and "moved or deleted" bar for the active tab.
struct DiskNoticeView: View {
    let state: AppState
    let doc: TextDocument
    let status: DiskStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange).accessibilityHidden(true)
            Text(status == .changed
                 ? "\(doc.title) changed on disk."
                 : "\(doc.title) was moved or deleted.")
                .font(.system(size: 12))
            switch status {
            case .changed:
                Button("Keep Mine") { state.keepMine(doc) }
                Button("Reload") { state.reloadFromDisk(doc) }
            case .missing:
                Button("Save As\u{2026}") { state.saveAs(doc) }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule()
    }
}

struct NoticeView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassCapsule()
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
