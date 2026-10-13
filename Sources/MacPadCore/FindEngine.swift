import Foundation

public struct FindOptions: Equatable, Sendable {
    public var matchCase: Bool
    public var wholeWord: Bool
    /// Treat the query as a regular expression. Replacements can use $1, $2 and so on for capture groups.
    public var regex: Bool

    public init(matchCase: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.regex = regex
    }
}

/// Pure search and replace over a text buffer. Ranges are UTF-16, as used by NSTextView.
public enum FindEngine {
    public static func matches(of query: String, in text: String, options: FindOptions = FindOptions()) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        if options.regex {
            guard let expression = expression(for: query, options: options) else { return [] }
            let full = NSRange(location: 0, length: (text as NSString).length)
            return expression.matches(in: text, range: full).map(\.range).filter { $0.length > 0 }
        }
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
        if options.regex {
            guard let expression = expression(for: query, options: options) else { return (text, 0) }
            let full = NSRange(location: 0, length: (text as NSString).length)
            let count = expression.numberOfMatches(in: text, range: full)
            guard count > 0 else { return (text, 0) }
            return (expression.stringByReplacingMatches(in: text, range: full, withTemplate: replacement), count)
        }
        let found = matches(of: query, in: text, options: options)
        guard !found.isEmpty else { return (text, 0) }
        let result = NSMutableString(string: text)
        for range in found.reversed() { result.replaceCharacters(in: range, with: replacement) }
        return (result as String, found.count)
    }

    /// The text that replaces one match. For regular expressions, capture groups in the template are expanded.
    public static func replacementText(
        for match: NSRange, in text: String, query: String, replacement: String, options: FindOptions = FindOptions()
    ) -> String {
        guard options.regex, let expression = expression(for: query, options: options),
              let found = expression.firstMatch(in: text, range: match) else { return replacement }
        return expression.replacementString(for: found, in: text, offset: 0, template: replacement)
    }

    /// Returns nil when the pattern is not a valid regular expression, so the find bar can show an error.
    public static func isValidPattern(_ query: String, options: FindOptions) -> Bool {
        !options.regex || expression(for: query, options: options) != nil
    }

    private static func expression(for query: String, options: FindOptions) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: query, options: options.matchCase ? [] : [.caseInsensitive])
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
