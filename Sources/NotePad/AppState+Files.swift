import AppKit
import NotePadCore

/// Opening, saving and reloading files, and checking them for changes on disk.
extension AppState {

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

    func openFile(_ url: URL, encoding: TextEncoding?) {
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

    func write(_ doc: TextDocument, to url: URL) -> Bool {
        do {
            try FileService.write(doc.text, to: url, encoding: doc.encoding, lineEnding: doc.lineEnding)
            doc.markSaved(to: url, modificationDate: FileService.modificationDate(of: url))
            updateDockBadge()
            diskStatus[doc.id] = nil
            persist(doc)
            recordVersion(of: doc)
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
}
