import Foundation
import Testing
@testable import MacPadCore

@Suite struct SnippetExpanderTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let epoch = Date(timeIntervalSince1970: 0)

    @Test func expandsDateAndTime() {
        let result = SnippetExpander.expand("{date} at {time}", at: epoch, calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
        #expect(result.text.contains("1970"))
        #expect(!result.text.contains("{date}"))
        #expect(!result.text.contains("{time}"))
        #expect(result.caretOffset == nil)
    }

    @Test func caretGoesToFirstCursorAndAllCursorsAreRemoved() {
        let result = SnippetExpander.expand("ab{cursor}cd{cursor}", at: epoch, calendar: calendar)
        #expect(result == SnippetExpander.Expansion(text: "abcd", caretOffset: 2))
    }

    @Test func caretOffsetCountsUTF16Units() {
        let result = SnippetExpander.expand("😀{cursor}x", at: epoch, calendar: calendar)
        #expect(result.caretOffset == 2)
        #expect(result.text == "😀x")
    }

    @Test func bodyWithoutPlaceholdersIsUnchanged() {
        let result = SnippetExpander.expand("plain text", at: epoch, calendar: calendar)
        #expect(result == SnippetExpander.Expansion(text: "plain text", caretOffset: nil))
    }
}

@Suite struct SnippetStoreTests {
    private func temporaryURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snippets.json")
    }

    @Test func missingFileLoadsAsEmpty() throws {
        let url = try temporaryURL()
        #expect(try SnippetStore.load(from: url).isEmpty)
    }

    @Test func savedSnippetsRoundTrip() throws {
        let url = try temporaryURL()
        let snippets = [Snippet(name: "Sig", body: "Thanks,\n{cursor}")]
        try SnippetStore.save(snippets, to: url)
        #expect(try SnippetStore.load(from: url) == snippets)
    }

    @Test func corruptFileThrowsAndIsNotOverwritten() throws {
        let url = try temporaryURL()
        try Data("not json".utf8).write(to: url)
        #expect(throws: SnippetStoreError.unreadable(url)) {
            try SnippetStore.load(from: url)
        }
        #expect(try Data(contentsOf: url) == Data("not json".utf8))
    }

    @Test func builtInIdsAreUnique() {
        #expect(Set(SnippetStore.builtIn.map(\.id)).count == SnippetStore.builtIn.count)
    }
}
