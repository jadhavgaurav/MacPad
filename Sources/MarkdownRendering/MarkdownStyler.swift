import Foundation
import Markdown

/// A styled range in the source text. Ranges are UTF-16, as used by NSTextStorage.
public struct StyleSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(Int)
        case strong
        case emphasis
        case strikethrough
        case inlineCode
        case codeBlock
        case link(String)
        case listMarker
        case quote
        /// Syntax characters such as `**` or `#`. Drawn dimmed, never removed from the text.
        case marker
    }

    public var kind: Kind
    public var range: NSRange
}

public enum MarkdownStyler {
    /// Styling is skipped above this size to keep typing responsive.
    public static let maximumUTF8Length = 1_000_000

    /// Spans in document order. Apply them in order, then apply `.marker` spans last so they stay dimmed.
    public static func spans(for text: String) -> [StyleSpan] {
        guard text.utf8.count <= maximumUTF8Length else { return [] }
        var walker = SpanWalker(source: text as NSString, table: OffsetTable(text))
        walker.visit(Document(parsing: text))
        return walker.spans
    }
}

/// Maps swift-markdown's (line, UTF-8 column) locations to UTF-16 offsets.
struct OffsetTable {
    private let lineStarts: [Int]
    private let utf16Offsets: [Int]

    init(_ text: String) {
        var starts = [0]
        var offsets: [Int] = []
        offsets.reserveCapacity(text.utf8.count + 1)
        var utf8Position = 0
        var utf16Position = 0
        for scalar in text.unicodeScalars {
            let width8 = UTF8.width(scalar)
            for _ in 0..<width8 { offsets.append(utf16Position) }
            utf8Position += width8
            utf16Position += scalar.value > 0xFFFF ? 2 : 1
            if scalar == "\n" { starts.append(utf8Position) }
        }
        offsets.append(utf16Position)
        lineStarts = starts
        utf16Offsets = offsets
    }

    /// UTF-16 range of the text on a 1-based line, excluding its newline.
    func lineRange(_ line: Int) -> NSRange? {
        guard line >= 1, line <= lineStarts.count else { return nil }
        let start = utf16Offsets[lineStarts[line - 1]]
        let end = line < lineStarts.count ? utf16Offsets[lineStarts[line]] - 1 : utf16Offsets[utf16Offsets.count - 1]
        return NSRange(location: start, length: max(0, end - start))
    }

    func range(of sourceRange: SourceRange) -> NSRange? {
        guard let lower = offset(of: sourceRange.lowerBound), let upper = offset(of: sourceRange.upperBound),
              upper >= lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    private func offset(of location: SourceLocation) -> Int? {
        guard location.line >= 1, location.line <= lineStarts.count, location.column >= 1 else { return nil }
        let utf8Offset = lineStarts[location.line - 1] + location.column - 1
        guard utf8Offset < utf16Offsets.count else { return nil }
        return utf16Offsets[utf8Offset]
    }
}

private struct SpanWalker: MarkupWalker {
    let source: NSString
    let table: OffsetTable
    var spans: [StyleSpan] = []

    init(source: NSString, table: OffsetTable) {
        self.source = source
        self.table = table
    }

    private func nsRange(_ markup: Markup) -> NSRange? { markup.range.flatMap(table.range(of:)) }

    /// Inline nodes inside lazy list continuations report columns offset by the list indent, which can fall outside
    /// the line. In that case, find the node's text on its line and widen it by `markerWidth` when markers surround it.
    private func inlineRange(_ markup: Markup, markerWidth: Int) -> NSRange? {
        if let exact = nsRange(markup) { return exact }
        guard let start = markup.range?.lowerBound, let line = table.lineRange(start.line) else { return nil }
        let text = Self.textContent(markup)
        guard !text.isEmpty else { return nil }
        let lineText = source.substring(with: line) as NSString
        let found = lineText.range(of: text)
        guard found.location != NSNotFound else { return nil }
        let content = NSRange(location: line.location + found.location, length: found.length)
        let markerEnd = content.location - markerWidth
        let markerTail = content.location + content.length + markerWidth
        guard markerWidth > 0, markerEnd >= 0, markerTail <= source.length else { return content }
        let marker = source.substring(with: NSRange(location: markerEnd, length: markerWidth))
        let tail = source.substring(with: NSRange(location: content.location + content.length, length: markerWidth))
        let markerCharacters: Set<Character> = ["*", "_", "~"]
        guard marker == tail, marker.allSatisfy({ markerCharacters.contains($0) }) else { return content }
        return NSRange(location: markerEnd, length: markerTail - markerEnd)
    }

    /// Concatenated text of an inline node, without its markup.
    private static func textContent(_ markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            if let text = child as? Text {
                result += text.string
            } else if let code = child as? InlineCode {
                result += code.code
            } else {
                result += textContent(child)
            }
        }
        return result
    }

    private mutating func add(_ kind: StyleSpan.Kind, _ range: NSRange?) {
        guard let range, range.length > 0 else { return }
        spans.append(StyleSpan(kind: kind, range: range))
    }

    private mutating func addEdgeMarkers(of range: NSRange, width: Int) {
        guard range.length >= width * 2 else { return }
        add(.marker, NSRange(location: range.location, length: width))
        add(.marker, NSRange(location: range.location + range.length - width, length: width))
    }

    mutating func visitHeading(_ heading: Heading) {
        if let range = nsRange(heading) {
            add(.heading(heading.level), range)
            var prefix = 0
            while range.location + prefix < source.length, prefix < range.length {
                let char = source.character(at: range.location + prefix)
                guard char == 0x23 || (prefix > 0 && (char == 0x20 || char == 0x09)) else { break }
                prefix += 1
            }
            if prefix > 0, source.character(at: range.location) == 0x23 {
                add(.marker, NSRange(location: range.location, length: prefix))
            }
        }
        descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = inlineRange(strong, markerWidth: 2) {
            add(.strong, range)
            addEdgeMarkers(of: range, width: 2)
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = inlineRange(emphasis, markerWidth: 1) {
            add(.emphasis, range)
            addEdgeMarkers(of: range, width: 1)
        }
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        if let range = nsRange(strikethrough) {
            add(.strikethrough, range)
            addEdgeMarkers(of: range, width: 2)
        }
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ code: InlineCode) {
        if let range = nsRange(code) {
            add(.inlineCode, range)
            var ticks = 0
            while ticks < range.length, source.character(at: range.location + ticks) == 0x60 { ticks += 1 }
            if ticks > 0 { addEdgeMarkers(of: range, width: ticks) }
        }
    }

    mutating func visitCodeBlock(_ block: CodeBlock) {
        add(.codeBlock, nsRange(block))
    }

    mutating func visitBlockQuote(_ quote: BlockQuote) {
        add(.quote, nsRange(quote))
        descendInto(quote)
    }

    mutating func visitLink(_ link: Link) {
        guard let range = nsRange(link) else { descendInto(link); return }
        add(.link(link.destination ?? ""), range)
        let firstChild = link.child(at: 0).flatMap { nsRange($0) }
        let lastChild = link.childCount > 0 ? link.child(at: link.childCount - 1).flatMap { nsRange($0) } : nil
        if let first = firstChild, let last = lastChild {
            add(.marker, NSRange(location: range.location, length: first.location - range.location))
            let lastEnd = last.location + last.length
            add(.marker, NSRange(location: lastEnd, length: range.location + range.length - lastEnd))
        }
        descendInto(link)
    }

    mutating func visitListItem(_ item: ListItem) {
        if let range = nsRange(item), let contentStart = item.child(at: 0).flatMap({ nsRange($0) })?.location,
           contentStart > range.location {
            add(.listMarker, NSRange(location: range.location, length: contentStart - range.location))
        }
        descendInto(item)
    }
}
