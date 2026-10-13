import Foundation
import Testing
@testable import MacPadCore

@Suite struct MarkdownFormatterTests {
    private func run(_ command: MarkdownCommand, _ text: String, _ location: Int, _ length: Int = 0) -> EditResult {
        MarkdownFormatter.apply(command, to: text, selection: NSRange(location: location, length: length))
    }

    // Bold and italic
    @Test func boldWrapsSelection() {
        let r = run(.bold, "make this bold", 5, 4)
        #expect(r.text == "make **this** bold")
        #expect(r.selection == NSRange(location: 7, length: 4))
    }
    @Test func boldUnwrapsWhenMarkersSurroundSelection() {
        let r = run(.bold, "make **this** bold", 7, 4)
        #expect(r.text == "make this bold")
        #expect(r.selection == NSRange(location: 5, length: 4))
    }
    @Test func boldUnwrapsWhenSelectionIncludesMarkers() {
        let r = run(.bold, "make **this** bold", 5, 8)
        #expect(r.text == "make this bold")
        #expect(r.selection == NSRange(location: 5, length: 4))
    }
    @Test func boldWithEmptySelectionInsertsMarkersAroundCaret() {
        let r = run(.bold, "ab", 1)
        #expect(r.text == "a****b")
        #expect(r.selection == NSRange(location: 3, length: 0))
    }
    @Test func boldTogglesOffAroundEmptyCaret() {
        let r = run(.bold, "a****b", 3)
        #expect(r.text == "ab")
        #expect(r.selection == NSRange(location: 1, length: 0))
    }
    @Test func italicWrapsSelection() {
        let r = run(.italic, "very good", 0, 4)
        #expect(r.text == "*very* good")
        #expect(r.selection == NSRange(location: 1, length: 4))
    }
    @Test func italicUnwrapsSingleAsterisks() {
        #expect(run(.italic, "*very* good", 1, 4).text == "very good")
    }
    @Test func italicOnBoldTextAddsItInsteadOfRemovingBold() {
        #expect(run(.italic, "**very** good", 2, 4).text == "***very*** good")
    }
    @Test func boldOnItalicTextAddsIt() {
        #expect(run(.bold, "*very* good", 1, 4).text == "***very*** good")
    }
    @Test func boldOnBoldItalicRemovesOnlyBold() {
        #expect(run(.bold, "***very*** good", 3, 4).text == "*very* good")
    }
    @Test func wrapsEmojiSelectionsUsingUTF16Ranges() {
        let r = run(.bold, "\u{1F600} hi", 3, 2)
        #expect(r.text == "\u{1F600} **hi**")
    }

    // Headings
    @Test func headingAddsPrefix() {
        let r = run(.heading(1), "Title", 5)
        #expect(r.text == "# Title")
        #expect(r.selection == NSRange(location: 7, length: 0))
    }
    @Test func headingReplacesDifferentLevel() { #expect(run(.heading(2), "# Title", 3).text == "## Title") }
    @Test func headingTogglesOffAtSameLevel() { #expect(run(.heading(1), "# Title", 3).text == "Title") }
    @Test func headingAppliesToEveryTouchedLine() {
        #expect(run(.heading(3), "a\nb\nc", 0, 3).text == "### a\n### b\nc")
    }
    @Test func headingOnMiddleLineLeavesOthersAlone() {
        #expect(run(.heading(1), "a\nb\nc", 2).text == "a\n# b\nc")
    }
    @Test func clearHeadingRemovesAnyLevel() {
        #expect(run(.clearHeading, "### Title", 4).text == "Title")
        #expect(run(.clearHeading, "plain", 0).text == "plain")
    }
    @Test func headingReplacesBulletPrefix() { #expect(run(.heading(1), "- item", 2).text == "# item") }
    @Test func bulletReplacesHeadingPrefix() { #expect(run(.bulletList, "# Title", 2).text == "- Title") }
    @Test func numberedListReplacesHeadingPrefix() { #expect(run(.numberedList, "## Title", 3).text == "1. Title") }
    @Test func hashWithoutSpaceIsNotAHeading() { #expect(run(.heading(1), "#tag", 0).text == "# #tag") }

    // Lists
    @Test func bulletListPrefixesLines() { #expect(run(.bulletList, "a\nb", 0, 3).text == "- a\n- b") }
    @Test func bulletListTogglesOff() { #expect(run(.bulletList, "- a\n- b", 0, 7).text == "a\nb") }
    @Test func bulletListSkipsBlankLines() { #expect(run(.bulletList, "a\n\nb", 0, 4).text == "- a\n\n- b") }
    @Test func bulletListConvertsNumberedLines() { #expect(run(.bulletList, "1. a\n2. b", 0, 9).text == "- a\n- b") }
    @Test func numberedListNumbersLines() { #expect(run(.numberedList, "a\nb\nc", 0, 5).text == "1. a\n2. b\n3. c") }
    @Test func numberedListTogglesOff() { #expect(run(.numberedList, "1. a\n2. b", 0, 9).text == "a\nb") }
    @Test func numberedListConvertsBullets() { #expect(run(.numberedList, "- a\n- b", 0, 7).text == "1. a\n2. b") }

    // Links
    @Test func linkWrapsSelectionAndSelectsPlaceholderURL() {
        let r = run(.link(url: nil), "see docs now", 4, 4)
        #expect(r.text == "see [docs](https://) now")
        #expect(r.selection == NSRange(location: 11, length: 8))
    }
    @Test func linkWithURLPutsCaretAfter() {
        let r = run(.link(url: "https://a.com"), "go", 0, 2)
        #expect(r.text == "[go](https://a.com)")
        #expect(r.selection == NSRange(location: 19, length: 0))
    }
    @Test func linkWithEmptySelectionInsertsPlaceholderLabel() {
        #expect(run(.link(url: nil), "", 0).text == "[link text](https://)")
    }

    // Safety
    @Test func outOfRangeSelectionIsClamped() {
        #expect(run(.bold, "ab", 10, 5).text == "ab****")
    }
}
