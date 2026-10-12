import Foundation
import Observation

/// The model for one tab. The buffer always uses LF; `lineEnding` is applied when saving.
@Observable
public final class TextDocument: Identifiable {
    public let id: UUID
    public var text: String
    public var fileURL: URL?
    public var encoding: TextEncoding
    public var lineEnding: LineEnding
    public var isDirty: Bool
    public var selection: NSRange
    public var scrollOffsetY: Double
    public var zoom: Double
    /// `nil` means "use the default for this file type".
    public var wordWrapOverride: Bool?
    /// `nil` means "use the default for this file type".
    public var formattedOverride: Bool?
    public var previewVisible: Bool
    public var diskModificationDate: Date?

    public static let zoomRange: ClosedRange<Double> = 0.25...5

    public init(
        id: UUID = UUID(),
        text: String = "",
        fileURL: URL? = nil,
        encoding: TextEncoding = .utf8,
        lineEnding: LineEnding = .lf,
        isDirty: Bool = false
    ) {
        self.id = id
        self.text = text
        self.fileURL = fileURL
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.isDirty = isDirty
        self.selection = NSRange(location: 0, length: 0)
        self.scrollOffsetY = 0
        self.zoom = 1
        self.wordWrapOverride = nil
        self.formattedOverride = nil
        self.previewVisible = false
        self.diskModificationDate = nil
    }

    public convenience init(snapshot: TabSnapshot) {
        self.init(
            id: snapshot.id,
            text: snapshot.text,
            fileURL: snapshot.filePath.map { URL(fileURLWithPath: $0) },
            encoding: snapshot.encoding,
            lineEnding: snapshot.lineEnding,
            isDirty: snapshot.isDirty
        )
        selection = NSRange(location: snapshot.selectionLocation, length: snapshot.selectionLength)
        scrollOffsetY = snapshot.scrollOffsetY
        zoom = snapshot.zoom
        wordWrapOverride = snapshot.wordWrap
        formattedOverride = snapshot.formatted
        previewVisible = snapshot.previewVisible
        diskModificationDate = snapshot.diskModificationDate
    }

    public var title: String { fileURL?.lastPathComponent ?? "Untitled" }

    public var isMarkdown: Bool {
        guard let ext = fileURL?.pathExtension.lowercased() else { return false }
        return ["md", "markdown", "mdown"].contains(ext)
    }

    public func usesWordWrap(default defaultValue: Bool) -> Bool { wordWrapOverride ?? defaultValue }

    /// Formatted view is on for Markdown files by default, and can be turned on for any tab.
    public func usesFormattedView(formatAllText: Bool) -> Bool {
        formattedOverride ?? (isMarkdown || formatAllText)
    }

    public func adjustZoom(by factor: Double) {
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    public func markSaved(to url: URL, modificationDate: Date?) {
        fileURL = url
        diskModificationDate = modificationDate
        isDirty = false
    }

    public var snapshot: TabSnapshot {
        TabSnapshot(
            id: id,
            text: text,
            filePath: fileURL?.path,
            encoding: encoding,
            lineEnding: lineEnding,
            isDirty: isDirty,
            selectionLocation: selection.location,
            selectionLength: selection.length,
            scrollOffsetY: scrollOffsetY,
            zoom: zoom,
            wordWrap: wordWrapOverride,
            formatted: formattedOverride,
            previewVisible: previewVisible,
            diskModificationDate: diskModificationDate
        )
    }
}
