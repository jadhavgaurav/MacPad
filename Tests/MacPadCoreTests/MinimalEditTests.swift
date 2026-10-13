import Foundation
import Testing
@testable import MacPadCore

@Suite struct MinimalEditTests {
    private func apply(_ old: String, _ new: String) -> String {
        let edit = MinimalEdit(from: old, to: new)
        return (old as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    @Test func identicalTextIsANoOp() { #expect(MinimalEdit(from: "abc", to: "abc").isNoOp) }
    @Test func insertionInTheMiddle() {
        let edit = MinimalEdit(from: "ac", to: "abc")
        #expect(edit.range == NSRange(location: 1, length: 0))
        #expect(edit.replacement == "b")
    }
    @Test func deletionAtTheEnd() {
        let edit = MinimalEdit(from: "abc", to: "ab")
        #expect(edit.range == NSRange(location: 2, length: 1))
        #expect(edit.replacement.isEmpty)
    }
    @Test func replacementOfTheWholeText() { #expect(apply("abc", "xyz") == "xyz") }
    @Test func fromAndToEmpty() {
        #expect(apply("", "hello") == "hello")
        #expect(apply("hello", "") == "")
    }
    @Test func repeatedCharactersStillRoundTrip() {
        #expect(apply("aaaa", "aaa") == "aaa")
        #expect(apply("aaa", "aaaa") == "aaaa")
    }
    @Test func neverSplitsSurrogatePairs() {
        let old = "\u{1F600}\u{1F601}"
        let new = "\u{1F600}\u{1F602}"
        let edit = MinimalEdit(from: old, to: new)
        #expect(apply(old, new) == new)
        #expect(edit.range.location % 2 == 0 && edit.range.length % 2 == 0)
    }
    @Test func lineEditKeepsEverythingElse() {
        let old = "one\ntwo\nthree"
        let new = "one\n# two\nthree"
        let edit = MinimalEdit(from: old, to: new)
        #expect(edit.range == NSRange(location: 4, length: 0))
        #expect(edit.replacement == "# ")
    }
}
