import AppKit
import NotePadCore
import Observation

enum DiskStatus: Equatable {
    case changed
    case missing
}

@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    /// The window that opens at launch. Its ID is fixed, so tabs that stay in it need no window ID of their own.
    static let mainWindowID = UUID(uuidString: "6F2A0C4E-8B1D-4C7A-9E3F-000000000001")!

    var tabs: [TextDocument] = []
    /// The active tab of each window.
    var activeByWindow: [UUID: UUID] = [:]
    /// The windows other than the main one, each holding the tabs that were moved into it.
    var detachedWindowIDs: [UUID] = []
    /// The window that last became key. Menus, the toolbar and the status bar act on its active tab.
    var focusedWindowID = AppState.mainWindowID
    /// Where a torn-off window should appear, in screen coordinates. Used once, when the window opens.
    @ObservationIgnored var pendingPlacements: [UUID: NSPoint] = [:]
    var notice: String?
    var diskStatus: [UUID: DiskStatus] = [:]
    var gotoVisible = false
    /// The 1-based source line at the top of the editor, which the preview follows.
    var previewLine = 1
    /// The traffic lights are hidden in full screen, so the tab strip doesn't need to clear them.
    var isFullScreen = false
    var recoveryVisible = false
    var historyVisible = false
    /// Hides the tab strip, toolbar and footer, and centres the text in a narrower column.
    var focusMode = false
    /// Shown in the footer toggle. Remembered between launches.
    var showLineNumbers = UserDefaults.standard.bool(forKey: SettingsKey.showLineNumbers) {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: SettingsKey.showLineNumbers) }
    }
    let find = FindModel()
    let stats = StatsModel()
    let snippets = SnippetLibrary()
    @ObservationIgnored let history: VersionStore? = try? VersionStore(directory: VersionStore.defaultDirectory())

    /// True while the editor is scrolling to follow the preview, so that scroll is not reported back.
    @ObservationIgnored var isFollowingPreview = false
    @ObservationIgnored var coordinator: SessionCoordinator?
    @ObservationIgnored var sessionStore: SessionStore?
    @ObservationIgnored var editors: [UUID: EditorController] = [:]
    @ObservationIgnored var started = false
    @ObservationIgnored var pendingURLs: [URL] = []
    @ObservationIgnored var noticeTask: Task<Void, Never>?
    @ObservationIgnored var persistChain: Task<Void, Never>?

    /// Opens or closes a window for a torn-off tab. The window view sets these, since it owns the environment actions.
    @ObservationIgnored var openWindowAction: ((UUID) -> Void)?
    @ObservationIgnored var dismissWindowAction: ((UUID) -> Void)?

    var activeDocument: TextDocument? { tabs.first { $0.id == activeID } }
    var activeEditor: EditorController? { activeID.flatMap { editors[$0] } }

    // MARK: Startup and shutdown

    func start() async {
        guard !started else { return }
        started = true
        // Paths passed on the command line (for example `MacPad.app/Contents/MacOS/MacPad notes.txt`).
        pendingURLs += CommandLine.arguments.dropFirst().compactMap { argument -> URL? in
            let url = URL(fileURLWithPath: argument)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        do {
            let store = SessionStore(directory: try SessionStore.defaultDirectory())
            sessionStore = store
            let result = try store.restore()
            if result.isReadOnly {
                showNotice("This session was saved by a newer version of MacPad, so changes won't be remembered.")
            } else {
                coordinator = SessionCoordinator(store: store) { [weak self] error in
                    Task { @MainActor in self?.showNotice("Couldn't save your session. \(error.localizedDescription)") }
                }
            }
            tabs = result.snapshots.map(TextDocument.init(snapshot:))
            detachedWindowIDs = result.windowIDs.filter { window in tabs.contains { $0.windowID == window } }
            for doc in tabs where doc.windowID.map({ !detachedWindowIDs.contains($0) }) ?? false { doc.windowID = nil }
            if let active = result.activeTabID, tabs.contains(where: { $0.id == active && windowID(of: $0) == AppState.mainWindowID }) {
                activeByWindow[AppState.mainWindowID] = active
            }
            if result.quarantinedCount > 0 {
                let count = result.quarantinedCount
                showNotice("\(count) saved tab\(count == 1 ? "" : "s") couldn't be read and was set aside.")
            } else if result.recoveredOrphanCount > 0 {
                let count = result.recoveredOrphanCount
                showNotice("Recovered \(count) tab\(count == 1 ? "" : "s") from your last session.")
            }
        } catch {
            showNotice("Couldn't restore your last session. \(error.localizedDescription)")
        }
        if tabs(in: AppState.mainWindowID).isEmpty { newTab() }
        activeByWindow[AppState.mainWindowID] = activeByWindow[AppState.mainWindowID] ?? tabs(in: AppState.mainWindowID).first?.id
        for window in detachedWindowIDs {
            activeByWindow[window] = tabs(in: window).first?.id
            openWindowAction?(window)
        }
        persistManifest()
        let queued = pendingURLs
        pendingURLs = []
        if !queued.isEmpty { open(queued) }
        checkDisk()
        refreshStats(textChanged: true)
    }

    /// Writes every tab and the manifest. Awaited before the app quits.
    /// Waits for every queued session write, then writes the current state of every tab. Awaited before quit.
    func flushSession() async {
        guard let coordinator else { return }
        await persistChain?.value
        for doc in tabs { await coordinator.schedule(doc.snapshot) }
        await coordinator.flush()
        await coordinator.saveManifest(manifest)
    }

    // MARK: Tabs

    func controller(for doc: TextDocument) -> EditorController {
        if let existing = editors[doc.id] { return existing }
        let controller = EditorController(document: doc)
        controller.onEdit = { [weak self] doc in self?.documentEdited(doc) }
        controller.onSelectionChange = { [weak self] doc in self?.selectionChanged(doc) }
        controller.onZoom = { [weak self] factor in
            doc.adjustZoom(by: factor)
            self?.persist(doc)
        }
        controller.onScroll = { [weak self] doc, topLine in
            guard let self else { return }
            self.editorScrolled(doc, topLine: topLine)
            self.persist(doc)
        }
        editors[doc.id] = controller
        return controller
    }

    func newTab() { add(TextDocument()) }

    func remove(at index: Int) {
        let doc = tabs[index]
        let id = doc.id
        let window = windowID(of: doc)
        let position = tabs(in: window).firstIndex { $0.id == id } ?? 0
        tabs.remove(at: index)
        updateDockBadge()
        editors[id] = nil
        diskStatus[id] = nil
        enqueue { await $0.remove(id) }
        if activeByWindow[window] == id {
            let rest = tabs(in: window)
            activeByWindow[window] = rest.isEmpty ? nil : rest[min(position, rest.count - 1)].id
        }
        windowLostTab(window)
    }

    // MARK: Editing callbacks

    func documentEdited(_ doc: TextDocument) {
        persist(doc)
        updateDockBadge()
        guard doc.id == activeID else { return }
        find.refresh()
        refreshStats(textChanged: true)
    }

    func selectionChanged(_ doc: TextDocument) {
        persist(doc)
        guard doc.id == activeID else { return }
        refreshStats(textChanged: false)
    }

    func refreshStats(textChanged: Bool) {
        guard let doc = activeDocument else { return }
        stats.update(text: doc.text, selection: doc.selection, textChanged: textChanged)
    }

    // MARK: View commands

    func format(_ command: MarkdownCommand) { activeEditor?.apply(command) }

    func toggleFocusMode() { focusMode.toggle() }

    /// Save As for a read-only file: the user picks a new location, and the copy becomes writable.
    func saveAsCopy(_ doc: TextDocument) {
        if saveAs(doc) { doc.isReadOnly = false }
    }

    /// Runs a line command on the active tab. The change is one undo step, and the selection moves with the lines.
    func lineCommand(_ command: (String, NSRange) -> EditResult) {
        guard let doc = activeDocument, let editor = activeEditor else { return }
        let result = command(doc.text, doc.selection)
        editor.replaceWholeText(result.text, selecting: result.selection)
        editor.focus()
    }

    func toggleWordWrap() {
        guard let doc = activeDocument else { return }
        doc.wordWrapOverride = !doc.usesWordWrap(default: EditorSettings.current().wrapByDefault)
        persist(doc)
    }

    func toggleFormattedView() {
        guard let doc = activeDocument else { return }
        doc.formattedOverride = !doc.usesFormattedView(formatAllText: EditorSettings.current().formatAllText)
        persist(doc)
    }

    func togglePreview() {
        guard let doc = activeDocument else { return }
        doc.previewVisible.toggle()
        persist(doc)
    }

    func zoom(by factor: Double) {
        guard let doc = activeDocument else { return }
        doc.adjustZoom(by: factor)
        persist(doc)
    }

    func resetZoom() {
        guard let doc = activeDocument else { return }
        doc.zoom = 1
        persist(doc)
    }

    /// Moves the caret to the start of `line`. Returns false when the line doesn't exist.
    func goTo(line: Int) -> Bool {
        guard let doc = activeDocument, let range = LineLocator.range(ofLine: line, in: doc.text) else { return false }
        activeEditor?.select(range)
        activeEditor?.focus()
        return true
    }

    // MARK: Persistence

    var manifest: SessionManifest {
        SessionManifest(
            tabIDs: tabs.map(\.id),
            activeTabID: activeByWindow[AppState.mainWindowID],
            windowIDs: detachedWindowIDs
        )
    }

    /// Runs session writes one after another, in the order they were requested.
    /// Without this, an older snapshot could finish after a newer one and overwrite it.
    func enqueue(_ operation: @escaping @Sendable (SessionCoordinator) async -> Void) {
        guard let coordinator else { return }
        let previous = persistChain
        persistChain = Task {
            await previous?.value
            await operation(coordinator)
        }
    }

    func persist(_ doc: TextDocument) {
        let snapshot = doc.snapshot
        enqueue { await $0.schedule(snapshot) }
    }

    func persistManifest() {
        let manifest = manifest
        enqueue { await $0.saveManifest(manifest) }
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}
