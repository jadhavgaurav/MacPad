import Foundation

public struct DecodedFile: Equatable, Sendable {
    /// Text with every line ending normalized to LF.
    public var text: String
    public var encoding: TextEncoding
    public var lineEnding: LineEnding
    public var modificationDate: Date?
}

public enum FileServiceError: Error, Equatable, LocalizedError {
    case fileNotFound(URL)
    case permissionDenied(URL)
    case undecodable(URL, tried: [TextEncoding])
    case readFailed(URL, reason: String)
    case writeFailed(URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            "\(url.lastPathComponent) can't be found. It may have been moved or deleted."
        case .permissionDenied(let url):
            "NotePad doesn't have permission to access \(url.lastPathComponent)."
        case .undecodable(let url, let tried):
            "\(url.lastPathComponent) isn't valid \(tried.map(\.label).joined(separator: " or ")). Try reopening it with another encoding."
        case .readFailed(let url, let reason):
            "\(url.lastPathComponent) couldn't be opened. \(reason)"
        case .writeFailed(let url, let reason):
            "\(url.lastPathComponent) couldn't be saved. \(reason)"
        }
    }
}

public enum FileService {
    public static func read(_ url: URL, as forced: TextEncoding? = nil) throws -> DecodedFile {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw mapReadError(error, url: url)
        }
        let (rawText, encoding) = try decode(data, forced: forced, url: url)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return DecodedFile(
            text: LineEnding.normalizedToLF(rawText),
            encoding: encoding,
            lineEnding: LineEnding.detect(in: rawText),
            modificationDate: modified
        )
    }

    public static func write(_ text: String, to url: URL, encoding: TextEncoding, lineEnding: LineEnding) throws {
        let converted = lineEnding.applying(to: text)
        guard let body = converted.data(using: encoding.stringEncoding) else {
            throw FileServiceError.writeFailed(url, reason: "Some characters can't be saved as \(encoding.label).")
        }
        var data = Data(encoding.bom)
        data.append(body)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw mapWriteError(error, url: url)
        }
    }

    /// False when the file exists but the current user cannot write it, or when it is a locked file.
    public static func isWritable(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return FileManager.default.isWritableFile(atPath: url.path)
    }

    public static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func decode(_ data: Data, forced: TextEncoding?, url: URL) throws -> (String, TextEncoding) {
        let encoding = forced ?? TextEncoding.detect(in: data)
        let body = data.starts(with: encoding.bom) ? Data(data.dropFirst(encoding.bom.count)) : data
        guard let text = String(data: body, encoding: encoding.stringEncoding) else {
            let tried: [TextEncoding] = forced == nil && encoding == .windows1252 ? [.utf8, .windows1252] : [encoding]
            throw FileServiceError.undecodable(url, tried: tried)
        }
        return (text, encoding)
    }

    private static func mapReadError(_ error: Error, url: URL) -> FileServiceError {
        switch (error as? CocoaError)?.code {
        case .fileReadNoSuchFile, .fileNoSuchFile: .fileNotFound(url)
        case .fileReadNoPermission: .permissionDenied(url)
        default: .readFailed(url, reason: error.localizedDescription)
        }
    }

    private static func mapWriteError(_ error: Error, url: URL) -> FileServiceError {
        switch (error as? CocoaError)?.code {
        case .fileWriteNoPermission: .permissionDenied(url)
        default: .writeFailed(url, reason: error.localizedDescription)
        }
    }
}
