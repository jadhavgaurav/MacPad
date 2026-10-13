import Foundation

/// Pure text logic for multiple selections. Every range is in UTF-16 units, the unit NSTextView uses.
public enum MultiCursor {
    /// One replacement inside an edit, in the coordinates of the text before the edit.
    public struct Change: Equatable, Sendable {
        public let range: NSRange
        public let replacement: String

        public init(range: NSRange, replacement: String) {
            self.range = range
            self.replacement = replacement
        }
    }

    /// The text after an edit, plus the caret or selection ranges to restore.
    public struct Edit: Equatable, Sendable {
        public let text: String
        public let selections: [NSRange]
        /// The replacements that actually change the text, in position order. Each one can be applied on
        /// its own, last to first, so text between the carets is never rewritten.
        public let changes: [Change]

        public init(text: String, selections: [NSRange], changes: [Change] = []) {
            self.text = text
            self.selections = selections
            self.changes = changes
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

    public enum VerticalDirection: Sendable {
        case up
        case down
    }

    /// The offset on the line above or below `offset`, at the same column. A shorter line puts the caret
    /// at its end. Returns nil at the first or last line.
    public static func caretOnAdjacentLine(from offset: Int, direction: VerticalDirection, in text: String) -> Int? {
        let ns = text as NSString
        let offset = min(max(offset, 0), ns.length)
        let line = ns.lineRange(for: NSRange(location: offset, length: 0))
        let column = offset - line.location
        switch direction {
        case .up:
            guard line.location > 0 else { return nil }
            let previous = ns.lineRange(for: NSRange(location: line.location - 1, length: 0))
            return previous.location + min(column, contentLength(of: previous, in: ns))
        case .down:
            let nextStart = NSMaxRange(line)
            guard nextStart < ns.length else { return nil }
            let next = ns.lineRange(for: NSRange(location: nextStart, length: 0))
            return next.location + min(column, contentLength(of: next, in: ns))
        }
    }

    /// Adds a caret above the topmost selection or below the bottommost one. Returns nil when there is
    /// no line to add to, or the caret already exists.
    public static func addingCaret(_ direction: VerticalDirection, to selections: [NSRange], in text: String) -> [NSRange]? {
        guard let source = direction == .up
            ? selections.min(by: { $0.location < $1.location })
            : selections.max(by: { NSMaxRange($0) < NSMaxRange($1) }) else { return nil }
        let from = direction == .up ? source.location : NSMaxRange(source)
        guard let caret = caretOnAdjacentLine(from: from, direction: direction, in: text),
              !selections.contains(NSRange(location: caret, length: 0)) else { return nil }
        return selections + [NSRange(location: caret, length: 0)]
    }

    /// Option-click: adds a caret at `offset`, or removes it when a caret is already there.
    /// The last remaining selection is never removed.
    public static func togglingCaret(at offset: Int, in selections: [NSRange]) -> [NSRange] {
        let caret = NSRange(location: offset, length: 0)
        if selections.contains(caret) {
            let remaining = selections.filter { $0 != caret }
            return remaining.isEmpty ? selections : remaining
        }
        return selections + [caret]
    }

    /// Sorts the ranges and merges any that overlap or repeat. The range holding the primary (the range at
    /// index `primary` of the input) is moved to the end, so callers can treat the last range as the primary.
    public static func normalized(_ ranges: [NSRange], primary: Int) -> [NSRange] {
        guard !ranges.isEmpty else { return [] }
        let primaryRange = ranges[min(max(primary, 0), ranges.count - 1)]
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { ($0.location, $0.length) < ($1.location, $1.length) }) {
            if let last = merged.last, range == last || range.location < NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else {
                merged.append(range)
            }
        }
        let primaryIndex = merged.firstIndex {
            $0.location <= primaryRange.location && NSMaxRange(primaryRange) <= NSMaxRange($0)
        } ?? merged.count - 1
        let primaryMerged = merged.remove(at: primaryIndex)
        return merged + [primaryMerged]
    }

    /// Inserts `string` at every range. A range that is not empty is replaced.
    public static func insert(_ string: String, at ranges: [NSRange], in text: String) -> Edit {
        replace(ranges.map { ($0, string) }, in: text)
    }

    /// Backspace at every range. A range that is not empty is deleted. An empty range deletes the whole
    /// character before it, so emoji and combined characters are never split.
    public static func deleteBackward(at ranges: [NSRange], in text: String) -> Edit {
        let ns = text as NSString
        return replace(ranges.map { range in
            if range.length > 0 || range.location == 0 { return (range, "") }
            return (ns.rangeOfComposedCharacterSequence(at: range.location - 1), "")
        }, in: text)
    }

    /// Forward Delete at every range. A range that is not empty is deleted. An empty range deletes the whole
    /// character after it.
    public static func deleteForward(at ranges: [NSRange], in text: String) -> Edit {
        let ns = text as NSString
        return replace(ranges.map { range in
            if range.length > 0 || range.location >= ns.length { return (range, "") }
            return (ns.rangeOfComposedCharacterSequence(at: range.location), "")
        }, in: text)
    }

    /// Replaces each span and returns the new text. Each caret ends after its replacement. The carets come
    /// back in the same order as the spans, so the primary keeps its place. A span that overlaps or repeats
    /// an earlier one (by position) is dropped, and so is its caret.
    public static func replace(_ spans: [(range: NSRange, with: String)], in text: String) -> Edit {
        let ns = text as NSString
        let byPosition = spans.indices.sorted {
            (spans[$0].range.location, spans[$0].range.length) < (spans[$1].range.location, spans[$1].range.length)
        }
        var kept: [Int] = []
        for index in byPosition {
            let range = spans[index].range
            guard NSMaxRange(range) <= ns.length else { continue }
            if let last = kept.last {
                let previous = spans[last].range
                if range == previous || range.location < NSMaxRange(previous) { continue }
            }
            kept.append(index)
        }

        let result = NSMutableString(string: text)
        for index in kept.reversed() {
            result.replaceCharacters(in: spans[index].range, with: spans[index].with)
        }

        var shift = 0
        var caretForSpan: [Int: NSRange] = [:]
        for index in kept {
            let length = (spans[index].with as NSString).length
            caretForSpan[index] = NSRange(location: spans[index].range.location + shift + length, length: 0)
            shift += length - spans[index].range.length
        }
        let changes = kept.compactMap { index -> Change? in
            let span = spans[index]
            guard span.range.length > 0 || !span.with.isEmpty else { return nil }
            return Change(range: span.range, replacement: span.with)
        }
        return Edit(text: result as String, selections: spans.indices.compactMap { caretForSpan[$0] }, changes: changes)
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
