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

    /// Moves a tab into another window's tab strip, at the slot under `local`, a point in that window's content.
    func moveTab(_ id: UUID, toWindow target: UUID, at local: CGPoint) {
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        let source = windowID(of: doc)
        let frames = TabZoneRegistry.shared.zones[target]?.tabFrames ?? [:]
        let position = tabs(in: target).filter { $0.id != id && (frames[$0.id]?.midX ?? 0) < local.x }.count
        if activeByWindow[source] == id {
            activeByWindow[source] = tabs(in: source).first { $0.id != id }?.id
        }
        doc.windowID = target == AppState.mainWindowID ? nil : target
        moveTab(id, toPosition: position)
        activeByWindow[target] = id
        persist(doc)
        windowLostTab(source)
        TabZoneRegistry.shared.zones[target]?.window?.makeKeyAndOrderFront(nil)
    }

    /// Moves a tab into a new window of its own, which opens with that tab in front. `screenPoint` is where the
    /// drop happened, so the window can open under the cursor.
    func moveToNewWindow(_ id: UUID, at screenPoint: NSPoint? = nil) {
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        let source = windowID(of: doc)
        // A window's only tab has nowhere to go: moving it would just swap one empty window for another.
        guard tabs(in: source).count > 1 else { return }
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

    /// A window became the key window. Menus, the toolbar, find and the status bar follow it.
    func focusWindow(_ window: UUID) {
        guard focusedWindowID != window else { return }
        focusedWindowID = window
        find.refresh()
        refreshStats(textChanged: true)
        syncPreviewToActiveTab()
    }

    /// The windows that still hold tabs.
    private var windowsWithTabs: Set<UUID> { Set(tabs.map { windowID(of: $0) }) }

    /// When a window closes, its tabs move to another open window, so no tab or unsaved text is lost. The main
    /// window is preferred. If no other window is open (the app is quitting), the tabs stay where they are.
    func windowWasClosed(_ window: UUID) {
        let remaining = windowsWithTabs.subtracting([window])
        let orphaned = tabs(in: window)
        detachedWindowIDs.removeAll { $0 == window }
        activeByWindow[window] = nil
        guard !orphaned.isEmpty else {
            persistManifest()
            return
        }
        guard let home = remaining.contains(AppState.mainWindowID)
            ? AppState.mainWindowID : detachedWindowIDs.first(where: remaining.contains) else { return }
        for doc in orphaned {
            doc.windowID = home == AppState.mainWindowID ? nil : home
            persist(doc)
        }
        if activeByWindow[home] == nil { activeByWindow[home] = orphaned.first?.id }
        if focusedWindowID == window { focusedWindowID = home }
        persistManifest()
    }

    /// Runs after a window loses a tab. A window with no tabs closes, as long as another window is open. The last
    /// window left keeps one empty tab, so the app never shows nothing.
    func windowLostTab(_ window: UUID) {
        if tabs(in: window).isEmpty {
            let others = windowsWithTabs
            guard !others.isEmpty else {
                add(TextDocument(), in: window)
                return
            }
            detachedWindowIDs.removeAll { $0 == window }
            activeByWindow[window] = nil
            if focusedWindowID == window, let next = others.contains(AppState.mainWindowID) ? AppState.mainWindowID : others.first {
                focusedWindowID = next
            }
            dismissWindowAction?(window)
        }
        persistManifest()
        find.refresh()
        refreshStats(textChanged: true)
    }
}
