import Foundation

/// Live document counts shown in the status bar.
public struct TextStats: Equatable, Sendable {
    public var lines: Int
    public var words: Int
    public var characters: Int
    public var charactersWithoutSpaces: Int

    public static let empty = TextStats(lines: 0, words: 0, characters: 0, charactersWithoutSpaces: 0)

    public init(lines: Int, words: Int, characters: Int, charactersWithoutSpaces: Int) {
        self.lines = lines
        self.words = words
        self.characters = characters
        self.charactersWithoutSpaces = charactersWithoutSpaces
    }

    public init(_ text: String) {
        var lines = text.isEmpty ? 0 : 1
        var words = 0
        var characters = 0
        var withoutSpaces = 0
        var insideWord = false
        for character in text {
            characters += 1
            if character.isNewline { lines += 1 }
            if character.isWhitespace {
                insideWord = false
            } else {
                withoutSpaces += 1
                if !insideWord {
                    words += 1
                    insideWord = true
                }
            }
        }
        self.init(lines: lines, words: words, characters: characters, charactersWithoutSpaces: withoutSpaces)
    }
}
