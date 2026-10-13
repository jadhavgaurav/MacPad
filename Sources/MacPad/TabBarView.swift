import AppKit
import MacPadCore
import SwiftUI

/// The frame of each tab in the window's global space, used to work out where a dragged tab lands.
private struct TabFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The frame of the whole tab strip, in the window's global space.
private struct StripFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct TabBarView: View {
    let state: AppState
    let windowID: UUID
    @Local private var frames: [UUID: CGRect] = [:]
    @Local private var strip: CGRect = .zero

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(state.tabs(in: windowID)) { doc in
                        TabItemView(doc: doc, state: state, windowID: windowID, frames: frames)
                    }
                }
                .padding(.horizontal, 2)
                .onPreferenceChange(TabFrameKey.self) { frames = $0; publishZone() }
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
        .background(GeometryReader { proxy in
            Color.clear.preference(key: StripFrameKey.self, value: proxy.frame(in: .global))
        })
        .onPreferenceChange(StripFrameKey.self) { strip = $0; publishZone() }
    }

    /// Tells the window registry where this strip and its tabs are, so other windows can drop tabs here.
    private func publishZone() {
        TabZoneRegistry.shared.updateFrames(for: windowID, strip: strip, tabs: frames)
    }
}

private struct TabItemView: View {
    let doc: TextDocument
    let state: AppState
    let windowID: UUID
    let frames: [UUID: CGRect]
    @Local private var isHovering = false
    @Local private var dragOffset: CGFloat = 0

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
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TabFrameKey.self, value: [doc.id: proxy.frame(in: .global)])
        })
        .contentShape(Capsule())
        .pointingHandCursor()
        .onHover { isHovering = $0 }
        .onTapGesture { state.select(doc.id) }
        .accessibilityAction(.default) { state.select(doc.id) }
        .offset(x: dragOffset)
        .gesture(dragGesture)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(showsDirty ? "\(doc.title), unsaved" : doc.title)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in dragOffset = value.translation.width }
            .onEnded { value in
                dragOffset = 0
                finishDrag(translation: value.translation)
            }
    }

    /// A drop on another window's tab strip moves the tab there. A drop well away from every strip tears the tab off
    /// into its own window, under the cursor. Otherwise a sideways drop moves the tab to the slot where it was let go.
    private func finishDrag(translation: CGSize) {
        let hit = TabZoneRegistry.shared.target(atScreenPoint: NSEvent.mouseLocation)
        if let hit, hit.window != windowID {
            state.moveTab(doc.id, toWindow: hit.window, at: hit.local)
            return
        }
        let far = abs(translation.height) > (hit == nil ? 40 : 56)
        if far {
            state.moveToNewWindow(doc.id, at: NSEvent.mouseLocation)
            return
        }
        guard let frame = frames[doc.id] else { return }
        let centre = frame.midX + translation.width
        let others = state.tabs(in: windowID).filter { $0.id != doc.id }
        let position = others.filter { (frames[$0.id]?.midX ?? 0) < centre }.count
        withAnimation(.easeOut(duration: 0.15)) { state.moveTab(doc.id, toPosition: position) }
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
