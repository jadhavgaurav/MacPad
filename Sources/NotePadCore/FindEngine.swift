import Foundation

public struct FindOptions: Equatable, Sendable {
    public var matchCase: Bool
    public var wholeWord: Bool

    public init(matchCase: Bool = false, wholeWord: Bool = false) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
    }
}

/// Pure search and replace over a text buffer. Ranges are UTF-16, as used by NSTextView.
public enum FindEngine {
    public static func matches(of query: String, in text: String, options: FindOptions = FindOptions()) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let ns = text as NSString
        let compare: NSString.CompareOptions = options.matchCase ? [.literal] : [.caseInsensitive]
        var results: [NSRange] = []
        var searchStart = 0
        while searchStart < ns.length {
            let found = ns.range(of: query, options: compare, range: NSRange(location: searchStart, length: ns.length - searchStart))
            if found.location == NSNotFound { break }
            if !options.wholeWord || isWholeWord(found, in: ns) { results.append(found) }
            searchStart = found.location + max(found.length, 1)
        }
        return results
    }

    public static func replacingAll(
        _ query: String, with replacement: String, in text: String, options: FindOptions = FindOptions()
    ) -> (text: String, count: Int) {
        let found = matches(of: query, in: text, options: options)
        guard !found.isEmpty else { return (text, 0) }
        let result = NSMutableString(string: text)
        for range in found.reversed() { result.replaceCharacters(in: range, with: replacement) }
        return (result as String, found.count)
    }

    /// Index of the first match at or after `location`, wrapping to the first match. `nil` when there are none.
    public static func indexOfMatch(atOrAfter location: Int, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.firstIndex { $0.location >= location } ?? 0
    }

    /// Index of the last match that starts before `location`, wrapping to the last match.
    public static func indexOfMatch(before location: Int, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        return matches.lastIndex { $0.location < location } ?? matches.count - 1
    }

    private static func isWholeWord(_ range: NSRange, in ns: NSString) -> Bool {
        func isWordCharacter(_ unit: unichar) -> Bool {
            guard let scalar = Unicode.Scalar(unit) else { return true }
            return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
        let beforeIsWord = range.location > 0 && isWordCharacter(ns.character(at: range.location - 1))
        let end = range.location + range.length
        let afterIsWord = end < ns.length && isWordCharacter(ns.character(at: end))
        return !beforeIsWord && !afterIsWord
    }
}
