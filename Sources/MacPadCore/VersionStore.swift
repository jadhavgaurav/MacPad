import CryptoKit
import Foundation

/// One saved copy of a file, kept by `VersionStore`.
public struct SavedVersion: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    /// UTF-8 size of the text.
    public let byteCount: Int
    /// SHA-256 of the text, so an unchanged save is not stored twice.
    public let contentHash: String

    public init(id: UUID = UUID(), date: Date, byteCount: Int, contentHash: String) {
        self.id = id
        self.date = date
        self.byteCount = byteCount
        self.contentHash = contentHash
    }
}

public enum VersionStoreError: Error, Equatable, LocalizedError {
    case unreadableIndex(URL)
    case missingVersion(UUID)

    public var errorDescription: String? {
        switch self {
        case .unreadableIndex(let url): "The version history at \(url.path) could not be read."
        case .missingVersion: "That saved version is no longer available."
        }
    }
}

/// Keeps the text of a file each time it is saved, in its own folder per file, with size and count caps.
///
/// Layout: `<directory>/<hash of the file path>/index.json` lists the versions oldest first, and each version's
/// text is stored next to it as `<version id>.txt`.
public struct VersionStore: Sendable {
    public struct Limits: Sendable {
        /// The most versions kept for one file. The oldest go first.
        public var versionsPerFile: Int
        /// The most bytes kept for one file across its versions. The oldest go first.
        public var bytesPerFile: Int
        /// Saves larger than this are not kept at all.
        public var bytesPerVersion: Int

        public init(versionsPerFile: Int = 50, bytesPerFile: Int = 20_000_000, bytesPerVersion: Int = 2_000_000) {
            self.versionsPerFile = versionsPerFile
            self.bytesPerFile = bytesPerFile
            self.bytesPerVersion = bytesPerVersion
        }
    }

    public let directory: URL
    public let limits: Limits

    public init(directory: URL, limits: Limits = Limits()) {
        self.directory = directory
        self.limits = limits
    }

    /// `history` under the app's Application Support folder. `MACPAD_HISTORY_DIR` overrides it for tests and QA.
    public static func defaultDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MACPAD_HISTORY_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("NotePad/history", isDirectory: true)
    }

    /// Stores `text` as the newest version of `fileURL`. Returns nil, and stores nothing, when the text matches
    /// the newest version or is larger than `limits.bytesPerVersion`.
    @discardableResult
    public func record(_ text: String, for fileURL: URL, at date: Date = Date()) throws -> SavedVersion? {
        let data = Data(text.utf8)
        guard data.count <= limits.bytesPerVersion else { return nil }
        let hash = Self.hash(data)
        var index = try loadIndex(for: fileURL)
        if index.last?.contentHash == hash { return nil }

        let folder = folder(for: fileURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let version = SavedVersion(date: date, byteCount: data.count, contentHash: hash)
        try data.write(to: textURL(for: version, in: folder), options: .atomic)
        index.append(version)

        // Drop the oldest versions until both caps hold, always keeping the one just saved.
        while index.count > 1,
              index.count > limits.versionsPerFile || index.reduce(0, { $0 + $1.byteCount }) > limits.bytesPerFile {
            let oldest = index.removeFirst()
            try? FileManager.default.removeItem(at: textURL(for: oldest, in: folder))
        }
        try saveIndex(index, for: fileURL)
        return version
    }

    /// The saved versions of `fileURL`, newest first. A file with no history has none.
    public func versions(for fileURL: URL) throws -> [SavedVersion] {
        try loadIndex(for: fileURL).reversed()
    }

    /// The text of one saved version.
    public func text(of version: SavedVersion, for fileURL: URL) throws -> String {
        let url = textURL(for: version, in: folder(for: fileURL))
        guard let data = try? Data(contentsOf: url), let text = String(bytes: data, encoding: .utf8) else {
            throw VersionStoreError.missingVersion(version.id)
        }
        return text
    }

    // MARK: Storage

    private func folder(for fileURL: URL) -> URL {
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        return directory.appendingPathComponent(Self.hash(Data(path.utf8)), isDirectory: true)
    }

    private func textURL(for version: SavedVersion, in folder: URL) -> URL {
        folder.appendingPathComponent("\(version.id.uuidString).txt")
    }

    private func indexURL(for fileURL: URL) -> URL {
        folder(for: fileURL).appendingPathComponent("index.json")
    }

    private func loadIndex(for fileURL: URL) throws -> [SavedVersion] {
        let url = indexURL(for: fileURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SavedVersion].self, from: Data(contentsOf: url))
        } catch {
            throw VersionStoreError.unreadableIndex(url)
        }
    }

    private func saveIndex(_ index: [SavedVersion], for fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(index).write(to: indexURL(for: fileURL), options: .atomic)
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
