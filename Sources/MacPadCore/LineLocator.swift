import Foundation

/// Line and column math for the status bar and Go to Line.
public enum LineLocator {
    public struct Position: Equatable, Sendable {
        public var line: Int
        public var column: Int

        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
    }

    /// 1-based line and column of a UTF-16 location. Columns count characters, so an emoji is one column.
    public static func position(at location: Int, in text: String) -> Position {
        let ns = text as NSString
        let clamped = min(max(location, 0), ns.length)
        var line = 1
        var cursor = 0
        while cursor < clamped {
            let found = ns.range(of: "\n", options: .literal, range: NSRange(location: cursor, length: clamped - cursor))
            if found.location == NSNotFound { break }
            line += 1
            cursor = found.location + 1
        }
        let lineStart = ns.lineRange(for: NSRange(location: clamped, length: 0)).location
        let column = ns.substring(with: NSRange(location: lineStart, length: clamped - lineStart)).count + 1
        return Position(line: line, column: column)
    }

    public static func lineCount(in text: String) -> Int {
        var count = 1
        for unit in text.utf8 where unit == 0x0A { count += 1 }
        return count
    }

    /// A zero-length range at the start of `line` (1-based), or `nil` when the line does not exist.
    public static func range(ofLine line: Int, in text: String) -> NSRange? {
        guard line >= 1 else { return nil }
        let ns = text as NSString
        var position = 0
        for _ in 1..<max(line, 1) {
            let found = ns.range(of: "\n", options: .literal, range: NSRange(location: position, length: ns.length - position))
            if found.location == NSNotFound { return nil }
            position = found.location + 1
        }
        return NSRange(location: position, length: 0)
    }
}
