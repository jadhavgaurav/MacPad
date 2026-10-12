import Foundation
import NotePadCore

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

    /// Moves a tab into a new window of its own, which opens with that tab in front.
    func moveToNewWindow(_ id: UUID) {
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        let source = windowID(of: doc)
        let window = UUID()
        if activeByWindow[source] == id {
            activeByWindow[source] = tabs(in: source).first { $0.id != id }?.id
        }
        doc.windowID = window
        detachedWindowIDs.append(window)
        activeByWindow[window] = id
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
