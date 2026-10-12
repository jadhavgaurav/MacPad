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

    var tabs: [TextDocument] = []
    var activeID: UUID?
    var notice: String?
    var diskStatus: [UUID: DiskStatus] = [:]
    var gotoVisible = false
    var previewFraction = 0.0
    /// The traffic lights are hidden in full screen, so the tab strip doesn't need to clear them.
    var isFullScreen = false
    var recoveryVisible = false
    /// Shown in the footer toggle. Remembered between launches.
    var showLineNumbers = UserDefaults.standard.bool(forKey: SettingsKey.showLineNumbers) {
        didSet { UserDefaults.standard.set(showLineNumbers, forKey: SettingsKey.showLineNumbers) }
    }
    let find = FindModel()
    let stats = StatsModel()

    @ObservationIgnored private var coordinator: SessionCoordinator?
    @ObservationIgnored private var sessionStore: SessionStore?
    @ObservationIgnored private var editors: [UUID: EditorController] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingURLs: [URL] = []
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var persistChain: Task<Void, Never>?

    var activeDocument: TextDocument? { tabs.first { $0.id == activeID } }
    var activeEditor: EditorController? { activeID.flatMap { editors[$0] } }

    // MARK: Startup and shutdown

    func start() async {
        guard !started else { return }
        started = true
        // Paths passed on the command line (for example `NotePad.app/Contents/MacOS/NotePad notes.txt`).
        pendingURLs += CommandLine.arguments.dropFirst().compactMap { argument -> URL? in
            let url = URL(fileURLWithPath: argument)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        do {
            let store = SessionStore(directory: try SessionStore.defaultDirectory())
            sessionStore = store
            let result = try store.restore()
            if result.isReadOnly {
                showNotice("This session was saved by a newer version of NotePad, so changes won't be remembered.")
            } else {
                coordinator = SessionCoordinator(store: store) { [weak self] error in
                    Task { @MainActor in self?.showNotice("Couldn't save your session. \(error.localizedDescription)") }
                }
            }
            tabs = result.snapshots.map(TextDocument.init(snapshot:))
            activeID = result.activeTabID
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
        if tabs.isEmpty { newTab() }
        activeID = activeID ?? tabs.first?.id
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
        controller.onScroll = { [weak self] doc, fraction in
            guard let self else { return }
            if doc.id == self.activeID { self.previewFraction = fraction }
            self.persist(doc)
        }
        editors[doc.id] = controller
        return controller
    }

    func newTab() { add(TextDocument()) }

    // MARK: Recovery of set-aside tabs

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
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
        persistManifest()
        find.refresh()
        refreshStats(textChanged: true)
        activeEditor?.focus()
    }

    func cycleTab(by delta: Int) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == activeID }) else { return }
        select(tabs[(index + delta + tabs.count) % tabs.count].id)
    }

    func selectTab(number: Int) {
        guard !tabs.isEmpty else { return }
        select(number >= 9 ? tabs[tabs.count - 1].id : tabs[min(number - 1, tabs.count - 1)].id)
    }

    func moveTab(_ id: UUID, before target: UUID) {
        guard id != target,
              let from = tabs.firstIndex(where: { $0.id == id }),
              let to = tabs.firstIndex(where: { $0.id == target }) else { return }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        persistManifest()
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
        closeTabs(tabs.filter { $0.id != id }.map(\.id))
    }

    func closeTabs(after id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTabs(tabs.suffix(from: index + 1).map(\.id))
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

    private func add(_ doc: TextDocument) {
        tabs.append(doc)
        persist(doc)
        select(doc.id)
    }

    /// Shows the number of tabs with unsaved changes on the Dock icon, or nothing when there are none.
    func updateDockBadge() {
        let unsaved = tabs.filter { $0.isDirty && !($0.fileURL == nil && $0.text.isEmpty) }.count
        NSApp.dockTile.badgeLabel = unsaved > 0 ? String(unsaved) : nil
    }

    private func remove(at index: Int) {
        let id = tabs[index].id
        tabs.remove(at: index)
        updateDockBadge()
        editors[id] = nil
        diskStatus[id] = nil
        enqueue { await $0.remove(id) }
        if activeID == id { activeID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id }
        if tabs.isEmpty { newTab() } else { persistManifest(); find.refresh(); refreshStats(textChanged: true) }
    }

    // MARK: Files

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func open(_ urls: [URL]) {
        guard started else { pendingURLs += urls; return }
        for url in urls.map(\.standardizedFileURL) {
            if let existing = tabs.first(where: { $0.fileURL?.standardizedFileURL == url }) {
                select(existing.id)
            } else {
                openFile(url, encoding: nil)
            }
        }
    }

    private func openFile(_ url: URL, encoding: TextEncoding?) {
        do {
            let file = try FileService.read(url, as: encoding)
            let doc = TextDocument(text: file.text, fileURL: url, encoding: file.encoding, lineEnding: file.lineEnding)
            doc.isReadOnly = !FileService.isWritable(url)
            doc.diskModificationDate = file.modificationDate
            let pristine = tabs.count == 1 && tabs[0].fileURL == nil && tabs[0].text.isEmpty ? tabs[0] : nil
            add(doc)
            if let pristine, let index = tabs.firstIndex(where: { $0.id == pristine.id }) { remove(at: index) }
        } catch FileServiceError.undecodable(let failed, _) {
            let message = "Choose an encoding to try."
            if let chosen = Dialogs.chooseEncoding(for: failed, message: message) { openFile(url, encoding: chosen) }
        } catch {
            Dialogs.showError(error)
        }
    }

    @discardableResult
    func save(_ doc: TextDocument) -> Bool {
        guard let url = doc.fileURL, diskStatus[doc.id] != .missing else { return saveAs(doc) }
        return write(doc, to: url)
    }

    @discardableResult
    func saveAs(_ doc: TextDocument) -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = doc.fileURL?.lastPathComponent ?? "Untitled.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(doc, to: url)
    }

    private func write(_ doc: TextDocument, to url: URL) -> Bool {
        do {
            try FileService.write(doc.text, to: url, encoding: doc.encoding, lineEnding: doc.lineEnding)
            doc.markSaved(to: url, modificationDate: FileService.modificationDate(of: url))
            updateDockBadge()
            diskStatus[doc.id] = nil
            persist(doc)
            return true
        } catch {
            Dialogs.showError(error)
            return false
        }
    }

    func reopen(_ doc: TextDocument, as encoding: TextEncoding) {
        guard let url = doc.fileURL else { return }
        do {
            let file = try FileService.read(url, as: encoding)
            doc.encoding = file.encoding
            doc.lineEnding = file.lineEnding
            doc.diskModificationDate = file.modificationDate
            doc.isDirty = false
            controller(for: doc).reset(text: file.text)
            persist(doc)
            refreshStats(textChanged: true)
        } catch {
            Dialogs.showError(error)
        }
    }

    func setEncoding(_ encoding: TextEncoding, for doc: TextDocument) {
        doc.encoding = encoding
        doc.isDirty = true
        persist(doc)
    }

    func setLineEnding(_ lineEnding: LineEnding, for doc: TextDocument) {
        doc.lineEnding = lineEnding
        doc.isDirty = true
        persist(doc)
    }

    // MARK: Disk changes

    func checkDisk() {
        for doc in tabs {
            guard let url = doc.fileURL else { continue }
            let decision = DiskChangeDetector.decide(
                known: doc.diskModificationDate,
                current: FileService.modificationDate(of: url),
                isDirty: doc.isDirty
            )
            switch decision {
            case .unchanged: continue
            case .reload: reloadFromDisk(doc)
            case .conflict: diskStatus[doc.id] = .changed
            case .missing: diskStatus[doc.id] = .missing
            }
        }
    }

    func reloadFromDisk(_ doc: TextDocument) {
        guard let url = doc.fileURL else { return }
        do {
            let file = try FileService.read(url, as: doc.encoding)
            doc.lineEnding = file.lineEnding
            doc.diskModificationDate = file.modificationDate
            doc.isDirty = false
            diskStatus[doc.id] = nil
            controller(for: doc).reset(text: file.text)
            persist(doc)
            refreshStats(textChanged: true)
        } catch {
            Dialogs.showError(error)
        }
    }

    func keepMine(_ doc: TextDocument) {
        doc.diskModificationDate = doc.fileURL.flatMap(FileService.modificationDate(of:))
        diskStatus[doc.id] = nil
        persist(doc)
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

    private var manifest: SessionManifest { SessionManifest(tabIDs: tabs.map(\.id), activeTabID: activeID) }

    /// Runs session writes one after another, in the order they were requested.
    /// Without this, an older snapshot could finish after a newer one and overwrite it.
    private func enqueue(_ operation: @escaping @Sendable (SessionCoordinator) async -> Void) {
        guard let coordinator else { return }
        let previous = persistChain
        persistChain = Task {
            await previous?.value
            await operation(coordinator)
        }
    }

    private func persist(_ doc: TextDocument) {
        let snapshot = doc.snapshot
        enqueue { await $0.schedule(snapshot) }
    }

    private func persistManifest() {
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
