import Foundation

public enum LineEnding: String, Codable, Sendable, CaseIterable {
    case lf, crlf, cr

    public var label: String {
        switch self {
        case .lf: "LF"
        case .crlf: "CRLF"
        case .cr: "CR"
        }
    }

    public var terminator: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    /// The first line ending found in `text`, or `.lf` when the text has none.
    public static func detect(in text: String) -> LineEnding {
        var previousWasCR = false
        for byte in text.utf8 {
            if byte == 0x0A { return previousWasCR ? .crlf : .lf }
            if previousWasCR { return .cr }
            previousWasCR = byte == 0x0D
        }
        return previousWasCR ? .cr : .lf
    }

    /// Converts every CRLF and lone CR to LF. The editor buffer always uses LF.
    public static func normalizedToLF(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Converts an LF-only buffer to this line ending, for saving.
    public func applying(to lfText: String) -> String {
        self == .lf ? lfText : lfText.replacingOccurrences(of: "\n", with: terminator)
    }
}
