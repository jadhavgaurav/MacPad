import Foundation

public struct SessionManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var tabIDs: [UUID]
    public var activeTabID: UUID?
    /// Windows other than the main one, in the order they were opened. Missing in sessions saved before tear-off.
    public var windowIDs: [UUID]?

    public init(
        schemaVersion: Int = SessionManifest.currentSchemaVersion,
        tabIDs: [UUID],
        activeTabID: UUID?,
        windowIDs: [UUID]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.tabIDs = tabIDs
        self.activeTabID = activeTabID
        self.windowIDs = windowIDs
    }
}

public struct RestoreResult: Equatable, Sendable {
    public var snapshots: [TabSnapshot]
    public var activeTabID: UUID?
    public var quarantinedCount: Int
    public var recoveredOrphanCount: Int
    /// True when the manifest was written by a newer version. Nothing should be written back.
    public var isReadOnly: Bool
    /// Torn-off windows recorded in the manifest, in the order they were opened.
    public var windowIDs: [UUID] = []
}

/// Reads and writes the session directory. Every write is atomic (temp file, then rename).
public struct SessionStore: Sendable {
    public let directory: URL
    private var manifestURL: URL { directory.appendingPathComponent("manifest.json") }
    private var quarantineURL: URL { directory.appendingPathComponent("quarantine", isDirectory: true) }

    public init(directory: URL) { self.directory = directory }

    /// `~/Library/Application Support/NotePad/session`, or the folder named by `NOTEPAD_SESSION_DIR`
    /// (used by tests and visual QA so they never touch the real session).
    public static func defaultDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["NOTEPAD_SESSION_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("NotePad/session", isDirectory: true)
    }

    public func save(_ snapshot: TabSnapshot) throws {
        try ensureDirectory()
        try JSONEncoder().encode(snapshot).write(to: tabURL(snapshot.id), options: .atomic)
    }

    public func saveManifest(_ manifest: SessionManifest) throws {
        try ensureDirectory()
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
    }

    public func remove(_ id: UUID) throws {
        let url = tabURL(id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func restore() throws -> RestoreResult {
        try ensureDirectory()
        var quarantined = 0
        var manifest: SessionManifest?

        if let data = try? Data(contentsOf: manifestURL) {
            if let decoded = try? JSONDecoder().decode(SessionManifest.self, from: data) {
                manifest = decoded
            } else {
                try quarantine(manifestURL)
                quarantined += 1
            }
        }
        if let manifest, manifest.schemaVersion > SessionManifest.currentSchemaVersion {
            return RestoreResult(snapshots: [], activeTabID: nil, quarantinedCount: 0, recoveredOrphanCount: 0, isReadOnly: true)
        }

        var byID: [UUID: TabSnapshot] = [:]
        var modified: [UUID: Date] = [:]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        for file in files where file.pathExtension == "json" && file.lastPathComponent != "manifest.json" {
            do {
                let snapshot = try JSONDecoder().decode(TabSnapshot.self, from: Data(contentsOf: file))
                byID[snapshot.id] = snapshot
                modified[snapshot.id] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            } catch {
                try quarantine(file)
                quarantined += 1
            }
        }

        var ordered: [TabSnapshot] = []
        for id in manifest?.tabIDs ?? [] {
            if let snapshot = byID.removeValue(forKey: id) { ordered.append(snapshot) }
        }
        let orphans = byID.values.sorted {
            (modified[$0.id] ?? .distantPast, $0.id.uuidString) < (modified[$1.id] ?? .distantPast, $1.id.uuidString)
        }
        ordered.append(contentsOf: orphans)

        let active = manifest?.activeTabID.flatMap { id in ordered.contains { $0.id == id } ? id : nil } ?? ordered.first?.id
        return RestoreResult(
            snapshots: ordered, activeTabID: active, quarantinedCount: quarantined,
            recoveredOrphanCount: orphans.count, isReadOnly: false, windowIDs: manifest?.windowIDs ?? []
        )
    }

    private func tabURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A session file that could not be read at launch and was moved aside.
    public struct QuarantinedFile: Identifiable, Equatable, Sendable {
        public var id: String { url.lastPathComponent }
        public let url: URL
        public let setAside: Date
        /// The start of the file's raw contents, for a quick look before recovering.
        public let preview: String
    }

    public func quarantinedFiles() throws -> [QuarantinedFile] {
        guard FileManager.default.fileExists(atPath: quarantineURL.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: quarantineURL, includingPropertiesForKeys: nil)
        return files.filter { $0.pathExtension == "json" }.map { url in
            let stamp = url.lastPathComponent.split(separator: "-").first.flatMap { Double($0) } ?? 0
            let raw = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return QuarantinedFile(url: url, setAside: Date(timeIntervalSince1970: stamp), preview: String(raw.prefix(300)))
        }.sorted { $0.setAside > $1.setAside }
    }

    /// Turns a set-aside file back into a tab. A readable tab keeps its text. An unreadable file becomes a tab
    /// holding its raw contents, so no text is lost. The file is removed once recovered.
    public func recover(_ file: QuarantinedFile) throws -> TabSnapshot {
        let data = try Data(contentsOf: file.url)
        let snapshot: TabSnapshot
        if let decoded = try? JSONDecoder().decode(TabSnapshot.self, from: data) {
            snapshot = TabSnapshot(
                text: decoded.text, filePath: decoded.filePath, encoding: decoded.encoding, lineEnding: decoded.lineEnding,
                isDirty: true, zoom: decoded.zoom
            )
        } else {
            snapshot = TabSnapshot(text: String(data: data, encoding: .utf8) ?? "", isDirty: true)
        }
        try FileManager.default.removeItem(at: file.url)
        return snapshot
    }

    /// Deletes a set-aside file the user no longer wants.
    public func discard(_ file: QuarantinedFile) throws {
        try FileManager.default.removeItem(at: file.url)
    }

    private func quarantine(_ file: URL) throws {
        try FileManager.default.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
        let target = quarantineURL.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(file.lastPathComponent)")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: file, to: target)
    }
}
