import Testing
@testable import MacPadCore

@Suite struct LineEndingTests {
    @Test func detectsLF() { #expect(LineEnding.detect(in: "a\nb") == .lf) }
    @Test func detectsCRLF() { #expect(LineEnding.detect(in: "a\r\nb") == .crlf) }
    @Test func detectsLoneCR() { #expect(LineEnding.detect(in: "a\rb") == .cr) }
    @Test func detectsTrailingCR() { #expect(LineEnding.detect(in: "a\r") == .cr) }
    @Test func defaultsToLFWithoutBreaks() { #expect(LineEnding.detect(in: "abc") == .lf) }
    @Test func usesTheFirstEnding() { #expect(LineEnding.detect(in: "a\r\nb\nc") == .crlf) }
    @Test func normalizesEverythingToLF() { #expect(LineEnding.normalizedToLF("a\r\nb\rc\nd") == "a\nb\nc\nd") }
    @Test func appliesCRLF() { #expect(LineEnding.crlf.applying(to: "a\nb") == "a\r\nb") }
    @Test func appliesLFUnchanged() { #expect(LineEnding.lf.applying(to: "a\nb") == "a\nb") }
    @Test func labels() { #expect(LineEnding.allCases.map(\.label) == ["LF", "CRLF", "CR"]) }
}
