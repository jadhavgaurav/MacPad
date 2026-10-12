import Foundation

/// A reusable block of text. `{date}`, `{time}` and `{cursor}` are expanded when the snippet is inserted.
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var body: String

    public init(id: UUID = UUID(), name: String, body: String) {
        self.id = id
        self.name = name
        self.body = body
    }
}

/// Expands the placeholders in a snippet body.
public enum SnippetExpander {
    public static let datePlaceholder = "{date}"
    public static let timePlaceholder = "{time}"
    public static let cursorPlaceholder = "{cursor}"

    public struct Expansion: Equatable, Sendable {
        public let text: String
        /// UTF-16 offset into `text` where the caret goes. `nil` when the body has no `{cursor}`.
        public let caretOffset: Int?

        public init(text: String, caretOffset: Int?) {
            self.text = text
            self.caretOffset = caretOffset
        }
    }

    private static func format(
        _ date: Date, dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style, calendar: Calendar, locale: Locale
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    /// Replaces `{date}` and `{time}` with the given moment, then removes every `{cursor}` and records
    /// the position of the first one.
    public static func expand(
        _ body: String,
        at date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> Expansion {
        let dateText = format(date, dateStyle: .medium, timeStyle: .none, calendar: calendar, locale: locale)
        let timeText = format(date, dateStyle: .none, timeStyle: .short, calendar: calendar, locale: locale)
        let filled = body
            .replacingOccurrences(of: datePlaceholder, with: dateText)
            .replacingOccurrences(of: timePlaceholder, with: timeText)

        guard let firstCursor = filled.range(of: cursorPlaceholder) else {
            return Expansion(text: filled, caretOffset: nil)
        }
        let caret = filled[..<firstCursor.lowerBound].utf16.count
        let text = filled.replacingOccurrences(of: cursorPlaceholder, with: "")
        return Expansion(text: text, caretOffset: caret)
    }
}

/// Snippets shipped with the app, plus the user's own, stored as JSON.
public enum SnippetStore {
    public static let builtIn: [Snippet] = [
        Snippet(
            id: UUID(uuidString: "5E1A0001-0000-4000-8000-000000000001")!,
            name: "Meeting Notes",
            body: "# Meeting Notes\n\n**Date:** {date}\n**Attendees:** \n\n## Agenda\n\n- {cursor}\n\n## Actions\n\n- [ ] \n"
        ),
        Snippet(
            id: UUID(uuidString: "5E1A0001-0000-4000-8000-000000000002")!,
            name: "Daily Log",
            body: "## {date}\n\n- {time} {cursor}\n"
        ),
        Snippet(
            id: UUID(uuidString: "5E1A0001-0000-4000-8000-000000000003")!,
            name: "To-Do List",
            body: "- [ ] {cursor}\n- [ ] \n- [ ] \n"
        ),
        Snippet(
            id: UUID(uuidString: "5E1A0001-0000-4000-8000-000000000004")!,
            name: "Code Block",
            body: "```\n{cursor}\n```\n"
        ),
        Snippet(
            id: UUID(uuidString: "5E1A0001-0000-4000-8000-000000000005")!,
            name: "Table",
            body: "| Column | Column |\n| --- | --- |\n| {cursor} | |\n"
        ),
        Snippet(
            id: UUID(uuidString: "5E1A0001-0000-4000-8000-000000000006")!,
            name: "Date and Time",
            body: "{date} {time}{cursor}"
        ),
    ]

    /// `snippets.json` under the app's Application Support folder.
    public static func defaultURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("NotePad/snippets.json")
    }

    /// Returns the saved snippets. A missing file means none yet.
    public static func load(from url: URL) throws -> [Snippet] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([Snippet].self, from: Data(contentsOf: url))
        } catch {
            throw SnippetStoreError.unreadable(url)
        }
    }

    /// Writes the snippets atomically, creating the folder when needed.
    public static func save(_ snippets: [Snippet], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snippets).write(to: url, options: .atomic)
    }
}

public enum SnippetStoreError: Error, Equatable, LocalizedError {
    case unreadable(URL)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unreadable(let url): "The snippets file at \(url.path) could not be read, so it was left unchanged."
        case .unavailable: "Snippets cannot be saved because the Application Support folder is unavailable."
        }
    }
}
