import Foundation

/// Pure text logic for multiple selections. Every range is in UTF-16 units, the unit NSTextView uses.
public enum MultiCursor {
    /// The text after an edit, plus the caret or selection ranges to restore.
    public struct Edit: Equatable, Sendable {
        public let text: String
        public let selections: [NSRange]

        public init(text: String, selections: [NSRange]) {
            self.text = text
            self.selections = selections
        }
    }

    /// The next match of the most recent selection that is not already selected. The search runs forward
    /// from that selection and wraps to the start of the text. Returns nil when there is no new match.
    public static func nextOccurrence(in text: String, selections: [NSRange]) -> NSRange? {
        let ns = text as NSString
        guard let anchor = selections.last, anchor.length > 0, NSMaxRange(anchor) <= ns.length else { return nil }
        let needle = ns.substring(with: anchor)
        let taken = Set(selections.map { "\($0.location):\($0.length)" })

        var from = NSMaxRange(anchor)
        while from <= ns.length {
            let search = NSRange(location: from, length: ns.length - from)
            let found = ns.range(of: needle, options: .literal, range: search)
            guard found.location != NSNotFound else { break }
            if !taken.contains("\(found.location):\(found.length)") { return found }
            from = found.location + 1
        }
        // Wrap around to the start of the text, stopping before the anchor.
        var wrapped = 0
        while wrapped < anchor.location {
            let search = NSRange(location: wrapped, length: anchor.location - wrapped)
            let found = ns.range(of: needle, options: .literal, range: search)
            guard found.location != NSNotFound else { break }
            if !taken.contains("\(found.location):\(found.length)") { return found }
            wrapped = found.location + 1
        }
        return nil
    }

    /// A rectangular selection between two offsets: one range per line, from the smaller column to the larger.
    /// Lines shorter than the left column get an empty range (a caret) at their end.
    public static func columnSelection(anchor: Int, head: Int, in text: String) -> [NSRange] {
        let ns = text as NSString
        let anchor = min(max(anchor, 0), ns.length)
        let head = min(max(head, 0), ns.length)
        let anchorLine = ns.lineRange(for: NSRange(location: anchor, length: 0))
        let headLine = ns.lineRange(for: NSRange(location: head, length: 0))
        let left = min(anchor - anchorLine.location, head - headLine.location)
        let right = max(anchor - anchorLine.location, head - headLine.location)

        var ranges: [NSRange] = []
        var lineStart = min(anchorLine.location, headLine.location)
        let lastStart = max(anchorLine.location, headLine.location)
        while true {
            let line = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            let content = contentLength(of: line, in: ns)
            let start = line.location + min(left, content)
            let end = line.location + min(right, content)
            ranges.append(NSRange(location: start, length: end - start))
            if line.location >= lastStart { break }
            lineStart = NSMaxRange(line)
        }
        return ranges
    }

    /// Inserts `string` at every range. A range that is not empty is replaced.
    public static func insert(_ string: String, at ranges: [NSRange], in text: String) -> Edit {
        edit(text, replacing: ranges.map { ($0, string) })
    }

    /// Backspace at every range. A range that is not empty is deleted. An empty range deletes the character before it.
    public static func deleteBackward(at ranges: [NSRange], in text: String) -> Edit {
        edit(text, replacing: ranges.map { range in
            if range.length > 0 { return (range, "") }
            if range.location == 0 { return (range, "") }
            return (NSRange(location: range.location - 1, length: 1), "")
        })
    }

    /// Replaces each span and returns the new text. Each caret ends after its replacement.
    /// Spans that overlap or repeat are dropped, keeping the first one.
    static func edit(_ text: String, replacing spans: [(range: NSRange, with: String)]) -> Edit {
        let ns = text as NSString
        var ordered: [(range: NSRange, with: String)] = []
        for span in spans.sorted(by: { $0.range.location < $1.range.location }) {
            guard NSMaxRange(span.range) <= ns.length else { continue }
            if let last = ordered.last, span.range == last.range || span.range.location < NSMaxRange(last.range) { continue }
            ordered.append(span)
        }

        let result = NSMutableString(string: text)
        for span in ordered.reversed() {
            result.replaceCharacters(in: span.range, with: span.with)
        }

        var shift = 0
        var selections: [NSRange] = []
        for span in ordered {
            let length = (span.with as NSString).length
            let caret = span.range.location + shift + length
            selections.append(NSRange(location: caret, length: 0))
            shift += length - span.range.length
        }
        return Edit(text: result as String, selections: selections)
    }

    /// The length of a line without its line break.
    private static func contentLength(of line: NSRange, in ns: NSString) -> Int {
        var length = line.length
        while length > 0 {
            let unit = ns.character(at: line.location + length - 1)
            guard unit == 0x0A || unit == 0x0D else { break }
            length -= 1
        }
        return length
    }
}
