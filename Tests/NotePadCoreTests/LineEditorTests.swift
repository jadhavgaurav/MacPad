import Foundation
import Testing
@testable import NotePadCore

@Suite struct LineEditorTests {
    private func caret(_ location: Int, _ length: Int = 0) -> NSRange { NSRange(location: location, length: length) }

    // Duplicate
    @Test func duplicatesTheCurrentLineBelowIt() {
        let r = LineEditor.duplicate("one\ntwo\nthree", selection: caret(5))
        #expect(r.text == "one\ntwo\ntwo\nthree")
        #expect(r.selection == caret(8, 3))
    }
    @Test func duplicatesLastLineWithoutTrailingNewline() {
        #expect(LineEditor.duplicate("one\ntwo", selection: caret(5)).text == "one\ntwo\ntwo")
    }
    @Test func duplicatesEveryLineInASelection() {
        #expect(LineEditor.duplicate("a\nb\nc", selection: caret(0, 3)).text == "a\nb\na\nb\nc")
    }

    // Move
    @Test func movesLineUp() {
        let r = LineEditor.moveUp("one\ntwo\nthree", selection: caret(4))
        #expect(r.text == "two\none\nthree")
        #expect(r.selection == caret(0, 3))
    }
    @Test func moveUpOnFirstLineDoesNothing() {
        #expect(LineEditor.moveUp("one\ntwo", selection: caret(1)).text == "one\ntwo")
    }
    @Test func movesLineDown() {
        let r = LineEditor.moveDown("one\ntwo\nthree", selection: caret(0))
        #expect(r.text == "two\none\nthree")
        #expect(r.selection == caret(4, 3))
    }
    @Test func moveDownOnLastLineDoesNothing() {
        #expect(LineEditor.moveDown("one\ntwo", selection: caret(5)).text == "one\ntwo")
    }
    @Test func movingKeepsTrailingNewline() {
        #expect(LineEditor.moveUp("a\nb\n", selection: caret(2)).text == "b\na\n")
    }

    // Join
    @Test func joinsCurrentLineWithNext() {
        #expect(LineEditor.join("one  \n   two\nthree", selection: caret(0)).text == "one two\nthree")
    }
    @Test func joinsSelectedLines() {
        #expect(LineEditor.join("a\nb\nc", selection: caret(0, 3)).text == "a b\nc")
    }
    @Test func joinOnLastLineDoesNothing() {
        #expect(LineEditor.join("a\nb", selection: caret(2)).text == "a\nb")
    }

    // Sort
    @Test func sortsWholeDocumentWhenNoMultiLineSelection() {
        #expect(LineEditor.sort("pear\napple\nBanana", selection: caret(0)).text == "apple\nBanana\npear")
    }
    @Test func sortsOnlySelectedLines() {
        #expect(LineEditor.sort("zeta\nc\nb\na", selection: caret(5, 3)).text == "zeta\nb\nc\na")
    }
    @Test func sortKeepsTrailingNewline() {
        #expect(LineEditor.sort("b\na\n", selection: caret(0)).text == "a\nb\n")
    }

    // Remove duplicates
    @Test func removesDuplicatesKeepingFirstOccurrence() {
        #expect(LineEditor.removeDuplicates("a\nb\na\nc\nb", selection: caret(0)).text == "a\nb\nc")
    }
    @Test func duplicateRemovalIsCaseSensitive() {
        #expect(LineEditor.removeDuplicates("A\na\nA", selection: caret(0)).text == "A\na")
    }
    @Test func removesDuplicatesInSelectionOnly() {
        #expect(LineEditor.removeDuplicates("x\na\na\nx", selection: caret(2, 3)).text == "x\na\nx")
    }

    @Test func emptyTextStaysEmpty() {
        #expect(LineEditor.duplicate("", selection: caret(0)).text == "\n" || LineEditor.duplicate("", selection: caret(0)).text == "")
        #expect(LineEditor.sort("", selection: caret(0)).text == "")
        #expect(LineEditor.removeDuplicates("", selection: caret(0)).text == "")
    }
}
