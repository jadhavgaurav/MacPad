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
