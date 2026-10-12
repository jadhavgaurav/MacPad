import Foundation
import Testing
@testable import NotePadCore

@Suite struct MultiCursorNextOccurrenceTests {
    @Test func findsTheNextMatchAfterTheSelection() {
        let text = "cat dog cat dog cat"
        let next = MultiCursor.nextOccurrence(in: text, selections: [NSRange(location: 0, length: 3)])
        #expect(next == NSRange(location: 8, length: 3))
    }

    @Test func wrapsAroundToTheStart() {
        let text = "cat dog cat"
        let next = MultiCursor.nextOccurrence(in: text, selections: [NSRange(location: 8, length: 3)])
        #expect(next == NSRange(location: 0, length: 3))
    }

    @Test func skipsMatchesAlreadySelected() {
        let text = "a a a"
        let selections = [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)]
        #expect(MultiCursor.nextOccurrence(in: text, selections: selections) == NSRange(location: 4, length: 1))
    }

    @Test func returnsNilWhenEveryMatchIsSelected() {
        let text = "a a"
        let selections = [NSRange(location: 0, length: 1), NSRange(location: 2, length: 1)]
        #expect(MultiCursor.nextOccurrence(in: text, selections: selections) == nil)
    }

    @Test func returnsNilForAnEmptySelection() {
        #expect(MultiCursor.nextOccurrence(in: "abc", selections: [NSRange(location: 1, length: 0)]) == nil)
    }
}

@Suite struct MultiCursorColumnTests {
    @Test func selectsTheSameColumnsOnEachLine() {
        let text = "abcd\nefgh\nijkl"
        // Anchor at column 1 of line 1, head at column 3 of line 3.
        let ranges = MultiCursor.columnSelection(anchor: 1, head: 13, in: text)
        #expect(ranges == [NSRange(location: 1, length: 2), NSRange(location: 6, length: 2), NSRange(location: 11, length: 2)])
    }

    @Test func shortLinesGetACaretAtTheirEnd() {
        let text = "abcdef\nx\nabcdef"
        let ranges = MultiCursor.columnSelection(anchor: 2, head: 13, in: text)
        #expect(ranges[1] == NSRange(location: 8, length: 0))
        #expect(ranges[0] == NSRange(location: 2, length: 2))
    }

    @Test func draggingUpwardGivesTheSameRectangle() {
        let text = "abcd\nefgh"
        let down = MultiCursor.columnSelection(anchor: 1, head: 7, in: text)
        let up = MultiCursor.columnSelection(anchor: 7, head: 1, in: text)
        #expect(down == up)
    }
}

@Suite struct MultiCursorEditTests {
    @Test func insertsAtEveryCaret() {
        let edit = MultiCursor.insert("-", at: [NSRange(location: 0, length: 0), NSRange(location: 3, length: 0)], in: "ab\ncd")
        #expect(edit.text == "-ab\n-cd")
        #expect(edit.selections == [NSRange(location: 1, length: 0), NSRange(location: 5, length: 0)])
    }

    @Test func replacesEverySelection() {
        let edit = MultiCursor.insert("X", at: [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)], in: "foo bar")
        #expect(edit.text == "X X")
        #expect(edit.selections == [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
    }

    @Test func backspaceDeletesTheCharacterBeforeEachCaret() {
        let edit = MultiCursor.deleteBackward(at: [NSRange(location: 2, length: 0), NSRange(location: 5, length: 0)], in: "abcdefg")
        #expect(edit.text == "acdfg")
        #expect(edit.selections == [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
    }

    @Test func forwardDeleteRemovesTheCharacterAfterEachCaret() {
        let edit = MultiCursor.deleteForward(at: [NSRange(location: 0, length: 0), NSRange(location: 3, length: 0)], in: "abcdef")
        #expect(edit.text == "bcef")
        #expect(edit.selections == [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)])
    }

    @Test func forwardDeleteAtTheEndChangesNothing() {
        let edit = MultiCursor.deleteForward(at: [NSRange(location: 3, length: 0)], in: "abc")
        #expect(edit.text == "abc")
    }

    @Test func backspaceRemovesAWholeEmoji() {
        let text = "a😀\nb😀\n"
        let edit = MultiCursor.deleteBackward(at: [NSRange(location: 3, length: 0), NSRange(location: 7, length: 0)], in: text)
        #expect(edit.text == "a\nb\n")
        #expect(edit.selections == [NSRange(location: 1, length: 0), NSRange(location: 3, length: 0)])
    }

    @Test func forwardDeleteRemovesAWholeEmoji() {
        let edit = MultiCursor.deleteForward(at: [NSRange(location: 1, length: 0)], in: "a😀b")
        #expect(edit.text == "ab")
    }

    @Test func replaceReturnsCaretsInTheOrderOfTheSpans() {
        let edit = MultiCursor.replace([(NSRange(location: 4, length: 0), "x"), (NSRange(location: 0, length: 0), "y")], in: "abcdef")
        #expect(edit.text == "yabcdxef")
        #expect(edit.selections == [NSRange(location: 6, length: 0), NSRange(location: 1, length: 0)])
    }

    @Test func changesListOnlyRealReplacementsInPositionOrder() {
        let edit = MultiCursor.deleteBackward(
            at: [NSRange(location: 5, length: 0), NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)], in: "abcdef"
        )
        #expect(edit.changes == [
            MultiCursor.Change(range: NSRange(location: 1, length: 1), replacement: ""),
            MultiCursor.Change(range: NSRange(location: 4, length: 1), replacement: ""),
        ])
    }

    @Test func backspaceAtTheStartChangesNothing() {
        let edit = MultiCursor.deleteBackward(at: [NSRange(location: 0, length: 0)], in: "abc")
        #expect(edit.text == "abc")
        #expect(edit.selections == [NSRange(location: 0, length: 0)])
    }

    @Test func duplicateRangesCollapseToOneEdit() {
        let edit = MultiCursor.insert("!", at: [NSRange(location: 1, length: 0), NSRange(location: 1, length: 0)], in: "ab")
        #expect(edit.text == "a!b")
        #expect(edit.selections.count == 1)
    }
}

@Suite struct MultiCursorCaretTests {
    @Test func caretMovesUpKeepingTheColumn() {
        // "abcdef" / "ghi": column 4 on line 1 ("ef") is the line 2 end because line 2 is shorter.
        let text = "abcdef\nghi\n"
        #expect(MultiCursor.caretOnAdjacentLine(from: 10, direction: .up, in: text) == 3)
    }

    @Test func caretMovesDownKeepingTheColumn() {
        let text = "abcdef\nghijkl"
        #expect(MultiCursor.caretOnAdjacentLine(from: 2, direction: .down, in: text) == 9)
        #expect(MultiCursor.caretOnAdjacentLine(from: 5, direction: .down, in: text) == 12)
    }

    @Test func noCaretBeyondFirstOrLastLine() {
        let text = "one\ntwo"
        #expect(MultiCursor.caretOnAdjacentLine(from: 1, direction: .up, in: text) == nil)
        #expect(MultiCursor.caretOnAdjacentLine(from: 5, direction: .down, in: text) == nil)
    }

    @Test func addingCaretsGoesFromTheTopmostAndBottommostSelection() {
        // "aaaa" / "bbbb" / "cccc": the caret at offset 7 is column 2 of line 2.
        let text = "aaaa\nbbbb\ncccc"
        let start = [NSRange(location: 7, length: 0)]
        #expect(MultiCursor.addingCaret(.up, to: start, in: text) == [NSRange(location: 7, length: 0), NSRange(location: 2, length: 0)])
        #expect(MultiCursor.addingCaret(.down, to: start, in: text) == [NSRange(location: 7, length: 0), NSRange(location: 12, length: 0)])
    }

    @Test func addingCaretReturnsNilWhenItAlreadyExists() {
        let text = "aaaa\nbbbb"
        let selections = [NSRange(location: 2, length: 0), NSRange(location: 7, length: 0)]
        #expect(MultiCursor.addingCaret(.up, to: selections, in: text) == nil)
    }

    @Test func optionClickAddsThenRemovesACaret() {
        let start = [NSRange(location: 0, length: 0)]
        let added = MultiCursor.togglingCaret(at: 5, in: start)
        #expect(added.count == 2)
        let removed = MultiCursor.togglingCaret(at: 5, in: added)
        #expect(removed == start)
    }

    @Test func lastCaretIsNeverRemoved() {
        let start = [NSRange(location: 3, length: 0)]
        #expect(MultiCursor.togglingCaret(at: 3, in: start) == start)
    }
}

@Suite struct MultiCursorNormalizeTests {
    @Test func mergesOverlapsAndPutsThePrimaryLast() {
        let ranges = [
            NSRange(location: 8, length: 0), NSRange(location: 0, length: 3),
            NSRange(location: 2, length: 2), NSRange(location: 8, length: 0),
        ]
        #expect(MultiCursor.normalized(ranges, primary: 0) == [NSRange(location: 0, length: 4), NSRange(location: 8, length: 0)])
        #expect(MultiCursor.normalized(ranges, primary: 1) == [NSRange(location: 8, length: 0), NSRange(location: 0, length: 4)])
    }

    @Test func emptyInputStaysEmpty() {
        #expect(MultiCursor.normalized([], primary: 0).isEmpty)
    }
}
