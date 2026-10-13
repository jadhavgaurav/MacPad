import Foundation
import Testing
@testable import MacPadCore

@Suite struct SessionStoreTests {
    private func makeStore() -> SessionStore {
        SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func restoreOnEmptyDirectoryReturnsNothing() throws {
        let result = try makeStore().restore()
        #expect(result.snapshots.isEmpty)
        #expect(result.activeTabID == nil)
        #expect(!result.isReadOnly)
    }

    @Test func roundTripKeepsTabOrderAndActiveTab() throws {
        let store = makeStore()
        let a = TabSnapshot(text: "a"), b = TabSnapshot(text: "b"), c = TabSnapshot(text: "c")
        for snapshot in [a, b, c] { try store.save(snapshot) }
        try store.saveManifest(SessionManifest(tabIDs: [c.id, a.id, b.id], activeTabID: a.id))
        let result = try store.restore()
        #expect(result.snapshots.map(\.id) == [c.id, a.id, b.id])
        #expect(result.activeTabID == a.id)
        #expect(result.recoveredOrphanCount == 0)
    }

    @Test func unsavedTextSurvivesRestore() throws {
        let store = makeStore()
        let snapshot = TabSnapshot(text: "never saved \u{1F44D}", isDirty: true)
        try store.save(snapshot)
        try store.saveManifest(SessionManifest(tabIDs: [snapshot.id], activeTabID: snapshot.id))
        let restored = try store.restore().snapshots.first
        #expect(restored?.text == "never saved \u{1F44D}")
        #expect(restored?.isDirty == true)
    }

    @Test func corruptTabFileIsQuarantinedAndOthersRestore() throws {
        let store = makeStore()
        let good = TabSnapshot(text: "good")
        try store.save(good)
        try store.saveManifest(SessionManifest(tabIDs: [good.id], activeTabID: good.id))
        let badURL = store.directory.appendingPathComponent("\(UUID().uuidString).json")
        try Data("{ not json".utf8).write(to: badURL)
        let result = try store.restore()
        #expect(result.snapshots.map(\.id) == [good.id])
        #expect(result.quarantinedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: badURL.path))
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: store.directory.appendingPathComponent("quarantine"), includingPropertiesForKeys: nil
        )
        #expect(quarantined.count == 1)
    }

    @Test func orphanTabFilesAreRecovered() throws {
        let store = makeStore()
        let listed = TabSnapshot(text: "listed"), orphan = TabSnapshot(text: "orphan")
        try store.save(listed)
        try store.save(orphan)
        try store.saveManifest(SessionManifest(tabIDs: [listed.id], activeTabID: listed.id))
        let result = try store.restore()
        #expect(result.snapshots.map(\.id) == [listed.id, orphan.id])
        #expect(result.recoveredOrphanCount == 1)
    }

    @Test func manifestEntriesWithoutFilesAreSkipped() throws {
        let store = makeStore()
        let real = TabSnapshot(text: "real")
        try store.save(real)
        try store.saveManifest(SessionManifest(tabIDs: [UUID(), real.id], activeTabID: UUID()))
        let result = try store.restore()
        #expect(result.snapshots.map(\.id) == [real.id])
        #expect(result.activeTabID == real.id)
    }

    @Test func corruptManifestIsQuarantinedAndTabsAreStillRecovered() throws {
        let store = makeStore()
        let tab = TabSnapshot(text: "kept")
        try store.save(tab)
        try Data("garbage".utf8).write(to: store.directory.appendingPathComponent("manifest.json"))
        let result = try store.restore()
        #expect(result.snapshots.map(\.id) == [tab.id])
        #expect(result.quarantinedCount == 1)
        #expect(result.recoveredOrphanCount == 1)
    }

    @Test func newerSchemaIsReadOnlyAndUntouched() throws {
        let store = makeStore()
        try store.save(TabSnapshot(text: "x"))
        try store.saveManifest(SessionManifest(schemaVersion: 99, tabIDs: [], activeTabID: nil))
        let result = try store.restore()
        #expect(result.isReadOnly)
        #expect(result.snapshots.isEmpty)
        let manifest = try JSONDecoder().decode(
            SessionManifest.self, from: Data(contentsOf: store.directory.appendingPathComponent("manifest.json"))
        )
        #expect(manifest.schemaVersion == 99)
    }

    @Test func removeDeletesOnlyThatTab() throws {
        let store = makeStore()
        let a = TabSnapshot(text: "a"), b = TabSnapshot(text: "b")
        try store.save(a)
        try store.save(b)
        try store.remove(a.id)
        try store.remove(UUID())
        #expect(try store.restore().snapshots.map(\.id) == [b.id])
    }

    @Test func overwritingATabReplacesItsContent() throws {
        let store = makeStore()
        var snapshot = TabSnapshot(text: "v1")
        try store.save(snapshot)
        snapshot.text = "v2"
        try store.save(snapshot)
        #expect(try store.restore().snapshots.first?.text == "v2")
    }

    @Test func setAsideFilesAreListedWithPreview() throws {
        let store = makeStore()
        let badURL = store.directory.appendingPathComponent("\(UUID().uuidString).json")
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{ broken but text is here".utf8).write(to: badURL)
        _ = try store.restore()
        let files = try store.quarantinedFiles()
        #expect(files.count == 1)
        #expect(files.first?.preview.contains("broken but text is here") == true)
    }

    @Test func recoveringReadableFileKeepsItsText() throws {
        let store = makeStore()
        let tab = TabSnapshot(text: "saved away")
        try FileManager.default.createDirectory(at: store.directory.appendingPathComponent("quarantine"), withIntermediateDirectories: true)
        let url = store.directory.appendingPathComponent("quarantine/1700000000-\(tab.id.uuidString).json")
        try JSONEncoder().encode(tab).write(to: url)
        let file = try store.quarantinedFiles().first!
        let recovered = try store.recover(file)
        #expect(recovered.text == "saved away")
        #expect(recovered.isDirty)
        #expect(try store.quarantinedFiles().isEmpty)
    }

    @Test func recoveringUnreadableFileKeepsRawText() throws {
        let store = makeStore()
        let url = store.directory.appendingPathComponent("quarantine/1700000000-bad.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("raw words survive".utf8).write(to: url)
        let file = try store.quarantinedFiles().first!
        #expect(try store.recover(file).text == "raw words survive")
    }

    @Test func discardRemovesSetAsideFile() throws {
        let store = makeStore()
        let url = store.directory.appendingPathComponent("quarantine/1700000000-gone.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
        try store.discard(try store.quarantinedFiles().first!)
        #expect(try store.quarantinedFiles().isEmpty)
    }
}
