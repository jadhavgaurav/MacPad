import Foundation

/// The persisted form of one tab. One JSON file per tab in the session directory.
public struct TabSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var filePath: String?
    public var encoding: TextEncoding
    public var lineEnding: LineEnding
    public var isDirty: Bool
    public var selectionLocation: Int
    public var selectionLength: Int
    public var scrollOffsetY: Double
    public var zoom: Double
    public var wordWrap: Bool?
    public var formatted: Bool?
    public var previewVisible: Bool
    public var diskModificationDate: Date?

    public init(
        id: UUID = UUID(),
        text: String = "",
        filePath: String? = nil,
        encoding: TextEncoding = .utf8,
        lineEnding: LineEnding = .lf,
        isDirty: Bool = false,
        selectionLocation: Int = 0,
        selectionLength: Int = 0,
        scrollOffsetY: Double = 0,
        zoom: Double = 1,
        wordWrap: Bool? = nil,
        formatted: Bool? = nil,
        previewVisible: Bool = false,
        diskModificationDate: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.filePath = filePath
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.isDirty = isDirty
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.scrollOffsetY = scrollOffsetY
        self.zoom = zoom
        self.wordWrap = wordWrap
        self.formatted = formatted
        self.previewVisible = previewVisible
        self.diskModificationDate = diskModificationDate
    }
}
