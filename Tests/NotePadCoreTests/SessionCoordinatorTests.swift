import Foundation
import Testing
@testable import NotePadCore

@Suite struct SessionCoordinatorTests {
    private func makeStore() -> SessionStore {
        SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    @Test func debouncedSavesCoalesceIntoTheLastSnapshot() async throws {
        let store = makeStore()
        let coordinator = SessionCoordinator(store: store, delay: .milliseconds(40))
        var snapshot = TabSnapshot(text: "1")
        for value in ["1", "12", "123"] {
            snapshot.text = value
            await coordinator.schedule(snapshot)
        }
        try await Task.sleep(for: .seconds(1))
        #expect(try store.restore().snapshots.first?.text == "123")
    }

    @Test func nothingIsWrittenBeforeTheDelay() async throws {
        let store = makeStore()
        let coordinator = SessionCoordinator(store: store, delay: .seconds(5))
        await coordinator.schedule(TabSnapshot(text: "later"))
        #expect(try store.restore().snapshots.isEmpty)
    }

    @Test func flushWritesPendingSnapshotsImmediately() async throws {
        let store = makeStore()
        let coordinator = SessionCoordinator(store: store, delay: .seconds(5))
        let a = TabSnapshot(text: "a"), b = TabSnapshot(text: "b")
        await coordinator.schedule(a)
        await coordinator.schedule(b)
        await coordinator.flush()
        #expect(Set(try store.restore().snapshots.map(\.id)) == [a.id, b.id])
    }

    @Test func removeCancelsPendingWriteAndDeletesFile() async throws {
        let store = makeStore()
        let coordinator = SessionCoordinator(store: store, delay: .milliseconds(40))
        let snapshot = TabSnapshot(text: "gone")
        try store.save(snapshot)
        await coordinator.schedule(snapshot)
        await coordinator.remove(snapshot.id)
        try await Task.sleep(for: .seconds(1))
        #expect(try store.restore().snapshots.isEmpty)
    }

    @Test func manifestIsWrittenImmediately() async throws {
        let store = makeStore()
        let coordinator = SessionCoordinator(store: store)
        let tab = TabSnapshot(text: "x")
        try store.save(tab)
        await coordinator.saveManifest(SessionManifest(tabIDs: [tab.id], activeTabID: tab.id))
        #expect(try store.restore().activeTabID == tab.id)
    }
}
