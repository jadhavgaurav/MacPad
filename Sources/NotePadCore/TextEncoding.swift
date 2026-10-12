import Foundation

public enum TextEncoding: String, Codable, Sendable, CaseIterable {
    case utf8, utf8BOM, utf16LE, utf16BE, windows1252

    public var label: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf8BOM: "UTF-8 with BOM"
        case .utf16LE: "UTF-16 LE"
        case .utf16BE: "UTF-16 BE"
        case .windows1252: "Windows-1252"
        }
    }

    var bom: [UInt8] {
        switch self {
        case .utf8BOM: [0xEF, 0xBB, 0xBF]
        case .utf16LE: [0xFF, 0xFE]
        case .utf16BE: [0xFE, 0xFF]
        case .utf8, .windows1252: []
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: .utf8
        case .utf16LE: .utf16LittleEndian
        case .utf16BE: .utf16BigEndian
        case .windows1252: .windowsCP1252
        }
    }

    /// Detects the encoding from a byte-order mark, then UTF-8 validity, then falls back to Windows-1252.
    static func detect(in data: Data) -> TextEncoding {
        for candidate in [TextEncoding.utf8BOM, .utf16LE, .utf16BE] where data.starts(with: candidate.bom) {
            return candidate
        }
        return String(data: data, encoding: .utf8) != nil ? .utf8 : .windows1252
    }
}
