import AppKit
import NotePadCore
import SwiftUI

struct TabBarView: View {
    let state: AppState
    let windowID: UUID

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(state.tabs(in: windowID)) { doc in
                        TabItemView(doc: doc, state: state, windowID: windowID)
                    }
                }
                .padding(.horizontal, 2)
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.02),
                            .init(color: .black, location: 0.97), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            Button { state.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .foregroundStyle(.secondary)
            .help("New tab")
            .accessibilityLabel("New tab")
        }
        .padding(4)
        .frame(height: 38)
        .glassCapsule()
    }
}

private struct TabItemView: View {
    let doc: TextDocument
    let state: AppState
    let windowID: UUID
    @Local private var isHovering = false

    private var isActive: Bool { state.activeByWindow[windowID] == doc.id }
    private var showsDirty: Bool { doc.isDirty && !(doc.fileURL == nil && doc.text.isEmpty) }

    var body: some View {
        HStack(spacing: 8) {
            Text(doc.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailingSlot.frame(width: 16, height: 16)
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 96, maxWidth: 200)
        .frame(height: 30)
        .foregroundStyle(isActive ? .primary : .secondary)
        .background(Capsule().fill(isActive ? Color.accentColor.opacity(0.18) : isHovering ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Capsule())
        .pointingHandCursor()
        .onHover { isHovering = $0 }
        .onTapGesture { state.select(doc.id) }
        .accessibilityAction(.default) { state.select(doc.id) }
        .draggable(doc.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            withAnimation(.easeOut(duration: 0.15)) { state.moveTab(id, before: doc.id) }
            return true
        }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showsDirty ? "\(doc.title), unsaved" : doc.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var trailingSlot: some View {
        if isHovering {
            Button { state.closeTab(doc.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityLabel("Close \(doc.title)")
        } else if showsDirty {
            Circle().fill(.secondary).frame(width: 7, height: 7)
        } else if isActive {
            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Close") { state.closeTab(doc.id) }
        Button("Close Others") { state.closeOthers(keeping: doc.id) }
            .disabled(state.tabs(in: windowID).count < 2)
        Button("Close to the Right") { state.closeTabs(after: doc.id) }
            .disabled(state.tabs(in: windowID).last?.id == doc.id)
        Button("Move to New Window") { state.moveToNewWindow(doc.id) }
            .disabled(state.tabs(in: windowID).count < 2 && windowID != AppState.mainWindowID)
        if let url = doc.fileURL {
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
    }
}
