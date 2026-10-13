import AppKit
import Foundation
import MacPadCore

/// Window handling: which tabs each window shows, the active tab per window, moving a tab into its own window,
/// and what happens when a window closes or runs out of tabs.
extension AppState {
    /// The active tab of the focused window.
    var activeID: UUID? {
        get { activeByWindow[focusedWindowID] }
        set { activeByWindow[focusedWindowID] = newValue }
    }

    func windowID(of doc: TextDocument) -> UUID { doc.windowID ?? AppState.mainWindowID }

    /// The tabs shown in one window, in tab-bar order.
    func tabs(in window: UUID) -> [TextDocument] { tabs.filter { windowID(of: $0) == window } }

    /// The window that shows a tab.
    func window(of id: UUID) -> UUID? { tabs.first { $0.id == id }.map(windowID(of:)) }

    /// Moves a tab to a slot among the tabs of its window. `position` counts the other tabs in that window.
    func moveTab(_ id: UUID, toPosition position: Int) {
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        let window = windowID(of: doc)
        var order = tabs(in: window).map(\.id).filter { $0 != id }
        order.insert(id, at: min(max(position, 0), order.count))
        // Only this window's slots change, so tabs in other windows keep their places.
        let slots = tabs.indices.filter { windowID(of: tabs[$0]) == window }
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        for (slot, tabID) in zip(slots, order) {
            if let moved = byID[tabID] { tabs[slot] = moved }
        }
        persistManifest()
    }

    /// Moves a tab into a new window of its own, which opens with that tab in front. `screenPoint` is where the
    /// drop happened, so the window can open under the cursor.
    func moveToNewWindow(_ id: UUID, at screenPoint: NSPoint? = nil) {
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        let source = windowID(of: doc)
        let window = UUID()
        if activeByWindow[source] == id {
            activeByWindow[source] = tabs(in: source).first { $0.id != id }?.id
        }
        doc.windowID = window
        detachedWindowIDs.append(window)
        activeByWindow[window] = id
        pendingPlacements[window] = screenPoint
        persist(doc)
        openWindowAction?(window)
        windowLostTab(source)
    }

    /// Closing a torn-off window puts its tabs back in the main window, so no tab or unsaved text is lost.
    func windowWasClosed(_ window: UUID) {
        guard detachedWindowIDs.contains(window) else { return }
        detachedWindowIDs.removeAll { $0 == window }
        for doc in tabs(in: window) {
            doc.windowID = nil
            persist(doc)
        }
        activeByWindow[window] = nil
        if activeByWindow[AppState.mainWindowID] == nil {
            activeByWindow[AppState.mainWindowID] = tabs(in: AppState.mainWindowID).first?.id
        }
        persistManifest()
    }

    /// Runs after a window loses a tab. An empty torn-off window closes. The main window always keeps one tab.
    func windowLostTab(_ window: UUID) {
        if tabs(in: window).isEmpty {
            if window == AppState.mainWindowID {
                add(TextDocument(), in: window)
                return
            }
            detachedWindowIDs.removeAll { $0 == window }
            activeByWindow[window] = nil
            dismissWindowAction?(window)
        }
        persistManifest()
        find.refresh()
        refreshStats(textChanged: true)
    }
}
