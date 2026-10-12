import Foundation
import Testing
@testable import MarkdownRendering

@Suite struct MarkdownStylerTests {
    private func spans(_ text: String, _ kind: StyleSpan.Kind) -> [NSRange] {
        MarkdownStyler.spans(for: text).filter { $0.kind == kind }.map(\.range)
    }

    @Test func headingSpanAndMarker() {
        #expect(spans("# Title", .heading(1)) == [NSRange(location: 0, length: 7)])
        #expect(spans("# Title", .marker) == [NSRange(location: 0, length: 2)])
    }

    @Test func secondLevelHeadingMarkerCoversAllHashes() {
        #expect(spans("## Sub", .marker) == [NSRange(location: 0, length: 3)])
    }

    @Test func strongSpanWithEdgeMarkers() {
        #expect(spans("**bold**", .strong) == [NSRange(location: 0, length: 8)])
        #expect(spans("**bold**", .marker) == [NSRange(location: 0, length: 2), NSRange(location: 6, length: 2)])
    }

    @Test func emphasisSpanWithEdgeMarkers() {
        #expect(spans("a *it* b", .emphasis) == [NSRange(location: 2, length: 4)])
        #expect(spans("a *it* b", .marker) == [NSRange(location: 2, length: 1), NSRange(location: 5, length: 1)])
    }

    @Test func inlineCodeSpan() {
        #expect(spans("use `x` here", .inlineCode) == [NSRange(location: 4, length: 3)])
    }

    @Test func linkSpanKeepsDestinationAndMarkers() {
        let text = "[x](https://e.com)"
        #expect(spans(text, .link("https://e.com")) == [NSRange(location: 0, length: 18)])
        #expect(spans(text, .marker) == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 16)])
    }

    @Test func listMarkerSpan() {
        #expect(spans("- item", .listMarker) == [NSRange(location: 0, length: 2)])
    }

    @Test func orderedListMarkerSpan() {
        #expect(spans("1. item", .listMarker) == [NSRange(location: 0, length: 3)])
    }

    @Test func blockQuoteSpan() {
        #expect(!spans("> quoted", .quote).isEmpty)
    }

    @Test func codeBlockSpan() {
        #expect(!spans("```\ncode\n```", .codeBlock).isEmpty)
    }

    @Test func rangesUseUTF16AfterEmoji() {
        #expect(spans("\u{1F600} **b**", .strong) == [NSRange(location: 3, length: 5)])
    }

    @Test func rangesOnLaterLinesAreOffsetCorrectly() {
        #expect(spans("first\n\n**b**", .strong) == [NSRange(location: 7, length: 5)])
    }

    @Test func plainTextHasNoSpans() {
        #expect(MarkdownStyler.spans(for: "just words").isEmpty)
    }

    @Test func oversizedTextIsSkipped() {
        let text = String(repeating: "# a\n", count: MarkdownStyler.maximumUTF8Length / 4 + 10)
        #expect(MarkdownStyler.spans(for: text).isEmpty)
    }
}
