import Foundation

public enum MarkdownCommand: Equatable, Sendable {
    case bold
    case italic
    case heading(Int)
    /// Removes a heading prefix from every touched line ("Normal text").
    case clearHeading
    case bulletList
    case numberedList
    /// `nil` inserts a placeholder URL and selects it so the user can type over it.
    case link(url: String?)
}

public struct EditResult: Equatable, Sendable {
    public var text: String
    /// UTF-16 range, as used by NSTextView.
    public var selection: NSRange
}

/// Toggles Markdown syntax in plain text. Pure functions, no UI.
public enum MarkdownFormatter {
    public static func apply(_ command: MarkdownCommand, to text: String, selection: NSRange) -> EditResult {
        let ns = text as NSString
        let sel = clamped(selection, length: ns.length)
        switch command {
        case .bold: return toggleWrap(ns, sel, marker: "**", unwrapsWhen: { $0 >= 2 })
        case .italic: return toggleWrap(ns, sel, marker: "*", unwrapsWhen: { $0 % 2 == 1 })
        case .heading(let level): return setHeading(ns, sel, level: min(max(level, 1), 6))
        case .clearHeading: return transformLines(ns, sel) { line, _ in stripHeadingPrefix(line) }
        case .bulletList: return toggleList(ns, sel, numbered: false)
        case .numberedList: return toggleList(ns, sel, numbered: true)
        case .link(let url): return makeLink(ns, sel, url: url)
        }
    }

    // MARK: Inline wrapping

    private static func toggleWrap(
        _ ns: NSString, _ sel: NSRange, marker: String, unwrapsWhen: (Int) -> Bool
    ) -> EditResult {
        let markerLength = (marker as NSString).length
        let markerCharacter = (marker as NSString).character(at: 0)
        let start = sel.location
        let end = sel.location + sel.length

        var runBefore = 0
        while start - runBefore > 0, ns.character(at: start - runBefore - 1) == markerCharacter { runBefore += 1 }
        var runAfter = 0
        while end + runAfter < ns.length, ns.character(at: end + runAfter) == markerCharacter { runAfter += 1 }

        if runBefore >= markerLength, runAfter >= markerLength, runBefore == runAfter, unwrapsWhen(runBefore) {
            var result = ns.replacingCharacters(in: NSRange(location: end, length: markerLength), with: "") as NSString
            result = result.replacingCharacters(in: NSRange(location: start - markerLength, length: markerLength), with: "") as NSString
            return EditResult(text: result as String, selection: NSRange(location: start - markerLength, length: sel.length))
        }

        let selected = ns.substring(with: sel)
        if sel.length >= markerLength * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(markerLength).dropLast(markerLength))
            let result = ns.replacingCharacters(in: sel, with: inner)
            return EditResult(text: result, selection: NSRange(location: start, length: (inner as NSString).length))
        }

        let wrapped = marker + selected + marker
        let result = ns.replacingCharacters(in: sel, with: wrapped)
        return EditResult(text: result, selection: NSRange(location: start + markerLength, length: sel.length))
    }

    // MARK: Line-based commands

    private static func setHeading(_ ns: NSString, _ sel: NSRange, level: Int) -> EditResult {
        let firstLine = ns.substring(with: ns.lineRange(for: NSRange(location: sel.location, length: 0)))
        let currentLevel = headingPrefix(of: firstLine)?.level ?? 0
        let removing = currentLevel == level
        return transformLines(ns, sel) { line, _ in
            let body = stripHeadingPrefix(stripListPrefix(line))
            return removing ? body : String(repeating: "#", count: level) + " " + body
        }
    }

    private static func toggleList(_ ns: NSString, _ sel: NSRange, numbered: Bool) -> EditResult {
        let block = ns.substring(with: ns.lineRange(for: sel))
        let contentLines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let allMatch = !contentLines.isEmpty && contentLines.allSatisfy {
            numbered ? numberedPrefixLength($0) != nil : bulletPrefixLength($0) != nil
        }
        var counter = 0
        return transformLines(ns, sel) { line, _ in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            let body = stripHeadingPrefix(stripListPrefix(line))
            if allMatch { return stripListPrefix(line) }
            counter += 1
            return numbered ? "\(counter). \(body)" : "- \(body)"
        }
    }

    private static func makeLink(_ ns: NSString, _ sel: NSRange, url: String?) -> EditResult {
        let selected = ns.substring(with: sel)
        let label = selected.isEmpty ? "link text" : selected
        let target = url ?? "https://"
        let insertion = "[\(label)](\(target))"
        let result = ns.replacingCharacters(in: sel, with: insertion)
        let labelLength = (label as NSString).length
        if url == nil {
            return EditResult(
                text: result,
                selection: NSRange(location: sel.location + 1 + labelLength + 2, length: (target as NSString).length)
            )
        }
        return EditResult(text: result, selection: NSRange(location: sel.location + (insertion as NSString).length, length: 0))
    }

    /// Applies `transform` to every line touched by the selection and keeps the caret in place.
    private static func transformLines(
        _ ns: NSString, _ sel: NSRange, _ transform: (String, Int) -> String
    ) -> EditResult {
        let blockRange = ns.lineRange(for: sel)
        let block = ns.substring(with: blockRange)
        var lines = block.components(separatedBy: "\n")
        let hadTrailingNewline = block.hasSuffix("\n")
        if hadTrailingNewline { lines.removeLast() }

        var firstDelta = 0
        var totalDelta = 0
        var newLines: [String] = []
        for (index, line) in lines.enumerated() {
            let newLine = transform(line, index)
            let delta = (newLine as NSString).length - (line as NSString).length
            if index == 0 { firstDelta = delta }
            totalDelta += delta
            newLines.append(newLine)
        }
        let newBlock = newLines.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
        let result = ns.replacingCharacters(in: blockRange, with: newBlock)
        let location = max(blockRange.location, sel.location + firstDelta)
        let length = max(0, sel.length + totalDelta - firstDelta)
        return EditResult(text: result, selection: NSRange(location: location, length: length))
    }

    // MARK: Prefix helpers

    private static func headingPrefix(of line: String) -> (level: Int, length: Int)? {
        let scalars = Array(line.unicodeScalars)
        var hashes = 0
        while hashes < scalars.count, scalars[hashes] == "#" { hashes += 1 }
        guard (1...6).contains(hashes), hashes < scalars.count, scalars[hashes] == " " || scalars[hashes] == "\t" else {
            return nil
        }
        var length = hashes
        while length < scalars.count, scalars[length] == " " || scalars[length] == "\t" { length += 1 }
        return (hashes, String(String.UnicodeScalarView(scalars[0..<length])).utf16.count)
    }

    private static func stripHeadingPrefix(_ line: String) -> String {
        guard let prefix = headingPrefix(of: line) else { return line }
        return (line as NSString).substring(from: prefix.length)
    }

    private static func bulletPrefixLength(_ line: String) -> Int? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) { return 2 }
        return nil
    }

    private static func numberedPrefixLength(_ line: String) -> Int? {
        let scalars = Array(line.unicodeScalars)
        var digits = 0
        while digits < scalars.count, ("0"..."9").contains(scalars[digits]) { digits += 1 }
        guard digits > 0, digits + 1 < scalars.count, scalars[digits] == ".", scalars[digits + 1] == " " else { return nil }
        return digits + 2
    }

    private static func stripListPrefix(_ line: String) -> String {
        if let length = bulletPrefixLength(line) ?? numberedPrefixLength(line) {
            return (line as NSString).substring(from: length)
        }
        return line
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }
}
