import Foundation
import Testing
@testable import NotePadCore

@Suite struct FindEngineTests {
    private let sample = "The cat and the hat. Other things."

    @Test func findsCaseInsensitiveByDefault() {
        #expect(FindEngine.matches(of: "the", in: sample).map(\.location) == [0, 12, 22])
    }
    @Test func matchCaseNarrowsResults() {
        #expect(FindEngine.matches(of: "the", in: sample, options: FindOptions(matchCase: true)).map(\.location) == [12, 22])
    }
    @Test func wholeWordSkipsPartialMatches() {
        #expect(FindEngine.matches(of: "the", in: sample, options: FindOptions(wholeWord: true)).map(\.location) == [0, 12])
    }
    @Test func emptyQueryFindsNothing() { #expect(FindEngine.matches(of: "", in: sample).isEmpty) }
    @Test func matchesDoNotOverlap() { #expect(FindEngine.matches(of: "aa", in: "aaaa").map(\.location) == [0, 2]) }
    @Test func replacesAllAndCounts() {
        let result = FindEngine.replacingAll("the", with: "a", in: sample)
        #expect(result.text == "a cat and a hat. Oar things.")
        #expect(result.count == 3)
    }
    @Test func replaceAllWithNoMatchesLeavesTextAlone() {
        let result = FindEngine.replacingAll("zzz", with: "x", in: sample)
        #expect(result.text == sample)
        #expect(result.count == 0)
    }
    @Test func replacementCanBeLongerOrEmpty() {
        #expect(FindEngine.replacingAll("a", with: "", in: "banana").text == "bnn")
        #expect(FindEngine.replacingAll("a", with: "xyz", in: "aa").text == "xyzxyz")
    }
    @Test func nextMatchWrapsAround() {
        let found = FindEngine.matches(of: "the", in: sample)
        #expect(FindEngine.indexOfMatch(atOrAfter: 1, in: found) == 1)
        #expect(FindEngine.indexOfMatch(atOrAfter: 30, in: found) == 0)
        #expect(FindEngine.indexOfMatch(atOrAfter: 0, in: []) == nil)
    }
    @Test func previousMatchWrapsAround() {
        let found = FindEngine.matches(of: "the", in: sample)
        #expect(FindEngine.indexOfMatch(before: 12, in: found) == 0)
        #expect(FindEngine.indexOfMatch(before: 0, in: found) == 2)
    }
    @Test func rangesAreUTF16AfterEmoji() {
        #expect(FindEngine.matches(of: "x", in: "\u{1F600}x").first == NSRange(location: 2, length: 1))
    }
}

@Suite struct LineLocatorTests {
    @Test func startOfTextIsLine1Column1() { #expect(LineLocator.position(at: 0, in: "abc") == .init(line: 1, column: 1)) }
    @Test func positionOnSecondLine() { #expect(LineLocator.position(at: 5, in: "abc\ndef") == .init(line: 2, column: 2)) }
    @Test func positionAfterTrailingNewline() { #expect(LineLocator.position(at: 4, in: "abc\n") == .init(line: 2, column: 1)) }
    @Test func emojiCountsAsOneColumn() { #expect(LineLocator.position(at: 2, in: "\u{1F600}x") == .init(line: 1, column: 2)) }
    @Test func locationIsClamped() { #expect(LineLocator.position(at: 99, in: "ab") == .init(line: 1, column: 3)) }
    @Test func countsLines() {
        #expect(LineLocator.lineCount(in: "") == 1)
        #expect(LineLocator.lineCount(in: "a\nb\n") == 3)
    }
    @Test func findsLineStarts() {
        #expect(LineLocator.range(ofLine: 1, in: "ab\ncd") == NSRange(location: 0, length: 0))
        #expect(LineLocator.range(ofLine: 2, in: "ab\ncd") == NSRange(location: 3, length: 0))
        #expect(LineLocator.range(ofLine: 3, in: "ab\ncd\n") == NSRange(location: 6, length: 0))
    }
    @Test func rejectsMissingLines() {
        #expect(LineLocator.range(ofLine: 3, in: "ab\ncd") == nil)
        #expect(LineLocator.range(ofLine: 0, in: "ab") == nil)
    }
}
