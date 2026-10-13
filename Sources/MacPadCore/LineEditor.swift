import Foundation

/// Line-level editing commands. Pure functions: they take the text and selection and return the new text and selection.
/// The selection is UTF-16, as used by NSTextView.
public enum LineEditor {
    public static func duplicate(_ text: String, selection: NSRange) -> EditResult {
        var doc = LineDocument(text, selection: selection)
        let block = Array(doc.lines[doc.first...doc.last])
        doc.lines.insert(contentsOf: block, at: doc.last + 1)
        doc.first += block.count
        doc.last += block.count
        return doc.result()
    }

    public static func moveUp(_ text: String, selection: NSRange) -> EditResult {
        var doc = LineDocument(text, selection: selection)
        guard doc.first > 0 else { return doc.result() }
        let above = doc.lines.remove(at: doc.first - 1)
        doc.lines.insert(above, at: doc.last)
        doc.first -= 1
        doc.last -= 1
        return doc.result()
    }

    public static func moveDown(_ text: String, selection: NSRange) -> EditResult {
        var doc = LineDocument(text, selection: selection)
        guard doc.last < doc.lines.count - 1 else { return doc.result() }
        let below = doc.lines.remove(at: doc.last + 1)
        doc.lines.insert(below, at: doc.first)
        doc.first += 1
        doc.last += 1
        return doc.result()
    }

    /// Joins the selected lines into one, separated by single spaces. With no multi-line selection, joins the line with the next one.
    public static func join(_ text: String, selection: NSRange) -> EditResult {
        var doc = LineDocument(text, selection: selection)
        if doc.first == doc.last {
            guard doc.last < doc.lines.count - 1 else { return doc.result() }
            doc.last += 1
        }
        let parts = doc.lines[doc.first...doc.last]
        var joined = ""
        for (index, part) in parts.enumerated() {
            let piece = index == 0 ? trimmedTrailing(part) : trimmed(part)
            if piece.isEmpty { continue }
            joined += joined.isEmpty ? piece : " " + piece
        }
        doc.lines.replaceSubrange(doc.first...doc.last, with: [joined])
        doc.last = doc.first
        return doc.result()
    }

    /// Sorts the selected lines, or the whole document when the selection is on one line.
    public static func sort(_ text: String, selection: NSRange) -> EditResult {
        var doc = LineDocument(text, selection: selection, wholeDocumentIfSingleLine: true)
        let sorted = doc.lines[doc.first...doc.last].sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        doc.lines.replaceSubrange(doc.first...doc.last, with: sorted)
        return doc.result()
    }

    /// Removes repeated lines from the selection, or the whole document when the selection is on one line.
    /// The first occurrence of each line is kept, and comparison is case-sensitive.
    public static func removeDuplicates(_ text: String, selection: NSRange) -> EditResult {
        var doc = LineDocument(text, selection: selection, wholeDocumentIfSingleLine: true)
        var seen = Set<String>()
        var kept: [String] = []
        for line in doc.lines[doc.first...doc.last] where seen.insert(line).inserted {
            kept.append(line)
        }
        doc.lines.replaceSubrange(doc.first...doc.last, with: kept)
        doc.last = doc.first + max(kept.count, 1) - 1
        return doc.result()
    }

    private static func trimmed(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces)
    }

    private static func trimmedTrailing(_ line: String) -> String {
        var result = line
        while result.last == " " || result.last == "\t" { result.removeLast() }
        return result
    }
}

/// The document split into lines, with the first and last selected line indices.
/// A trailing newline is kept as a flag, so the line array never has an empty last entry.
struct LineDocument {
    var lines: [String]
    var hasTrailingNewline: Bool
    var first: Int
    var last: Int

    init(_ text: String, selection: NSRange, wholeDocumentIfSingleLine: Bool = false) {
        let ns = text as NSString
        hasTrailingNewline = text.hasSuffix("\n")
        var all = text.components(separatedBy: "\n")
        if hasTrailingNewline { all.removeLast() }
        lines = all

        let start = min(max(selection.location, 0), ns.length)
        let end = min(max(selection.location + selection.length, start), ns.length)
        // A selection that ends right after a newline does not include the next line.
        let effectiveEnd = end > start && ns.character(at: end - 1) == 0x0A ? end - 1 : end
        first = Self.lineIndex(at: start, in: ns)
        last = max(first, Self.lineIndex(at: effectiveEnd, in: ns))
        last = min(last, lines.count - 1)
        first = min(first, last)

        if wholeDocumentIfSingleLine && first == last {
            first = 0
            last = lines.count - 1
        }
    }

    /// The text after the edit, and the selection covering the edited lines.
    func result() -> EditResult {
        let text = lines.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
        let startOffset = offset(ofLine: first)
        let endOffset = offset(ofLine: last) + lines[last].utf16.count
        return EditResult(text: text, selection: NSRange(location: startOffset, length: endOffset - startOffset))
    }

    private func offset(ofLine index: Int) -> Int {
        lines[0..<index].reduce(0) { $0 + $1.utf16.count + 1 }
    }

    private static func lineIndex(at location: Int, in ns: NSString) -> Int {
        var count = 0
        var position = 0
        while position < location {
            if ns.character(at: position) == 0x0A { count += 1 }
            position += 1
        }
        return count
    }
}
