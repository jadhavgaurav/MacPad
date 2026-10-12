import AppKit
import NotePadCore

/// Tabs that could not be read at launch are set aside, so the user can recover or discard them.
extension AppState {

    func setAsideFiles() -> [SessionStore.QuarantinedFile] {
        (try? sessionStore?.quarantinedFiles()) ?? []
    }

    /// Turns a set-aside file back into a tab, then removes it from quarantine.
    func recover(_ file: SessionStore.QuarantinedFile) {
        guard let sessionStore else { return }
        do {
            let doc = TextDocument(snapshot: try sessionStore.recover(file))
            tabs.append(doc)
            persist(doc)
            select(doc.id)
            showNotice("Recovered \(doc.title) as a new tab.")
        } catch {
            Dialogs.showError(error)
        }
    }

    func discard(_ file: SessionStore.QuarantinedFile) {
        do {
            try sessionStore?.discard(file)
        } catch {
            Dialogs.showError(error)
        }
    }

    func select(_ id: UUID) {
        guard let doc = tabs.first(where: { $0.id == id }) else { return }
        activeByWindow[windowID(of: doc)] = id
        persistManifest()
        find.refresh()
        refreshStats(textChanged: true)
        syncPreviewToActiveTab()
        activeEditor?.focus()
    }

    func cycleTab(by delta: Int) {
        let shown = tabs(in: focusedWindowID)
        guard shown.count > 1, let index = shown.firstIndex(where: { $0.id == activeID }) else { return }
        select(shown[(index + delta + shown.count) % shown.count].id)
    }

    func selectTab(number: Int) {
        let shown = tabs(in: focusedWindowID)
        guard !shown.isEmpty else { return }
        select(number >= 9 ? shown[shown.count - 1].id : shown[min(number - 1, shown.count - 1)].id)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let doc = tabs[index]
        let isPristine = doc.fileURL == nil && doc.text.isEmpty
        if doc.isDirty && !isPristine {
            switch Dialogs.confirmClose(doc) {
            case .save: if !save(doc) { return }
            case .discard: break
            case .cancel: return
            }
        }
        remove(at: index)
    }

    func closeOthers(keeping id: UUID) {
        guard let window = window(of: id) else { return }
        closeTabs(tabs(in: window).filter { $0.id != id }.map(\.id))
    }

    func closeTabs(after id: UUID) {
        guard let window = window(of: id) else { return }
        let shown = tabs(in: window)
        guard let index = shown.firstIndex(where: { $0.id == id }) else { return }
        closeTabs(shown.suffix(from: index + 1).map(\.id))
    }

    /// Closes several tabs with one question about all of their unsaved changes, instead of one prompt per tab.
    func closeTabs(_ ids: [UUID]) {
        let targets = tabs.filter { ids.contains($0.id) }
        let unsaved = targets.filter { $0.isDirty && !($0.fileURL == nil && $0.text.isEmpty) }
        if !unsaved.isEmpty {
            switch Dialogs.confirmCloseMany(unsaved.map(\.title)) {
            case .saveAll:
                for doc in unsaved where !save(doc) { return }
            case .discardAll:
                break
            case .cancel:
                return
            }
        }
        for id in ids {
            if let index = tabs.firstIndex(where: { $0.id == id }) { remove(at: index) }
        }
    }

    /// Adds a tab to a window, which defaults to the focused one, and makes it that window's active tab.
    func add(_ doc: TextDocument, in window: UUID? = nil) {
        let target = window ?? focusedWindowID
        doc.windowID = target == AppState.mainWindowID ? nil : target
        tabs.append(doc)
        persist(doc)
        select(doc.id)
    }

    /// Shows the number of tabs with unsaved changes on the Dock icon, or nothing when there are none.
    func updateDockBadge() {
        let unsaved = tabs.filter { $0.isDirty && !($0.fileURL == nil && $0.text.isEmpty) }.count
        NSApp.dockTile.badgeLabel = unsaved > 0 ? String(unsaved) : nil
    }
}
