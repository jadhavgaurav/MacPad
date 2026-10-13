import Foundation
import Testing
@testable import MacPadCore

@Suite struct VersionStoreTests {
    private func makeStore(_ limits: VersionStore.Limits = VersionStore.Limits()) throws -> VersionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return VersionStore(directory: dir, limits: limits)
    }

    private let file = URL(fileURLWithPath: "/tmp/notes/todo.md")

    @Test func versionsComeBackNewestFirstWithTheirText() throws {
        let store = try makeStore()
        try store.record("first", for: file, at: Date(timeIntervalSince1970: 1))
        try store.record("second", for: file, at: Date(timeIntervalSince1970: 2))
        let versions = try store.versions(for: file)
        #expect(versions.count == 2)
        #expect(try store.text(of: versions[0], for: file) == "second")
        #expect(try store.text(of: versions[1], for: file) == "first")
    }

    @Test func anUnchangedSaveIsNotStoredTwice() throws {
        let store = try makeStore()
        #expect(try store.record("same", for: file) != nil)
        #expect(try store.record("same", for: file) == nil)
        #expect(try store.versions(for: file).count == 1)
    }

    @Test func theOldestVersionsGoPastTheCountCap() throws {
        let store = try makeStore(VersionStore.Limits(versionsPerFile: 3))
        for index in 1...5 { try store.record("v\(index)", for: file) }
        let texts = try store.versions(for: file).map { try store.text(of: $0, for: file) }
        #expect(texts == ["v5", "v4", "v3"])
    }

    @Test func theOldestVersionsGoPastTheByteCap() throws {
        let store = try makeStore(VersionStore.Limits(bytesPerFile: 10))
        try store.record("aaaa", for: file)
        try store.record("bbbb", for: file)
        try store.record("cccc", for: file)
        let texts = try store.versions(for: file).map { try store.text(of: $0, for: file) }
        #expect(texts == ["cccc", "bbbb"])
    }

    @Test func aSaveLargerThanTheVersionCapIsSkipped() throws {
        let store = try makeStore(VersionStore.Limits(bytesPerVersion: 4))
        #expect(try store.record("too long", for: file) == nil)
        #expect(try store.versions(for: file).isEmpty)
    }

    @Test func eachFileHasItsOwnHistory() throws {
        let store = try makeStore()
        try store.record("notes", for: file)
        #expect(try store.versions(for: URL(fileURLWithPath: "/tmp/notes/other.md")).isEmpty)
    }

    @Test func aCorruptIndexThrows() throws {
        let store = try makeStore()
        try store.record("text", for: file)
        let folder = try #require(FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil).first)
        let index = folder.appendingPathComponent("index.json")
        try Data("not json".utf8).write(to: index)
        // The temporary folder can be reported as /var or /private/var, so only the error type is compared.
        #expect(throws: VersionStoreError.self) { try store.versions(for: file) }
    }
}
