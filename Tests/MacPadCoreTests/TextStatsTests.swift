import Testing
@testable import MacPadCore

@Suite struct TextStatsTests {
    @Test func emptyTextHasNoCounts() { #expect(TextStats("") == .empty) }

    @Test func countsPlainSentence() {
        let stats = TextStats("hello brave world")
        #expect(stats == TextStats(lines: 1, words: 3, characters: 17, charactersWithoutSpaces: 15))
    }

    @Test func countsLinesIncludingTrailingEmptyLine() {
        #expect(TextStats("a\nb").lines == 2)
        #expect(TextStats("a\n").lines == 2)
        #expect(TextStats("\n\n").lines == 3)
    }

    @Test func tabsAndNewlinesSeparateWords() { #expect(TextStats("a\tb\nc  d").words == 4) }

    @Test func countsEmojiAsOneCharacter() {
        let stats = TextStats("a\u{1F44D}\u{1F3FD}b")
        #expect(stats.characters == 3)
        #expect(stats.charactersWithoutSpaces == 3)
    }

    @Test func cjkWordsAreWhitespaceDelimited() {
        let stats = TextStats("\u{4F60}\u{597D} \u{4E16}\u{754C}")
        #expect(stats.words == 2)
        #expect(stats.characters == 5)
        #expect(stats.charactersWithoutSpaces == 4)
    }

    @Test func whitespaceOnlyTextHasNoWords() {
        let stats = TextStats("  \n \t")
        #expect(stats.words == 0)
        #expect(stats.charactersWithoutSpaces == 0)
    }

    @Test func readingTimeRoundsUp() {
        #expect(TextStats.readingMinutes(words: 0) == 0)
        #expect(TextStats.readingMinutes(words: 1) == 1)
        #expect(TextStats.readingMinutes(words: 238) == 1)
        #expect(TextStats.readingMinutes(words: 239) == 2)
    }
}
