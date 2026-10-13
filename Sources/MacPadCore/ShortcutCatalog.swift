import Foundation

/// One keyboard shortcut or mouse gesture, as shown in the Shortcuts pane of Settings.
public struct ShortcutEntry: Equatable, Sendable, Identifiable {
    public let category: String
    public let action: String
    /// Key names as macOS menus show them, such as "⌘N" or "⌥⌘↑".
    public let keys: String

    public var id: String { "\(category)|\(action)" }

    public init(category: String, action: String, keys: String) {
        self.category = category
        self.action = action
        self.keys = keys
    }
}

/// Every shortcut the app uses. The Shortcuts pane reads this list, so keep it in step with the menus.
public enum ShortcutCatalog {
    public static let all: [ShortcutEntry] = [
        ShortcutEntry(category: "File", action: "New tab", keys: "⌘N"),
        ShortcutEntry(category: "File", action: "Open", keys: "⌘O"),
        ShortcutEntry(category: "File", action: "Save", keys: "⌘S"),
        ShortcutEntry(category: "File", action: "Close tab", keys: "⌘W"),
        ShortcutEntry(category: "Edit", action: "Undo", keys: "⌘Z"),
        ShortcutEntry(category: "Edit", action: "Redo", keys: "⇧⌘Z"),
        ShortcutEntry(category: "Edit", action: "Cut, copy and paste", keys: "⌘X, ⌘C, ⌘V"),
        ShortcutEntry(category: "Find", action: "Find", keys: "⌘F"),
        ShortcutEntry(category: "Find", action: "Find and replace", keys: "⌥⌘F"),
        ShortcutEntry(category: "Find", action: "Find next", keys: "⌘G"),
        ShortcutEntry(category: "Find", action: "Find previous", keys: "⇧⌘G"),
        ShortcutEntry(category: "Find", action: "Go to line", keys: "⌘L"),
        ShortcutEntry(category: "Multiple cursors", action: "Select next occurrence", keys: "⌘D"),
        ShortcutEntry(category: "Multiple cursors", action: "Add cursor above", keys: "⌥⌘↑"),
        ShortcutEntry(category: "Multiple cursors", action: "Add cursor below", keys: "⌥⌘↓"),
        ShortcutEntry(category: "Multiple cursors", action: "Add or remove a cursor where you click", keys: "⌥ click"),
        ShortcutEntry(category: "Multiple cursors", action: "Select a column", keys: "⇧⌥ drag"),
        ShortcutEntry(category: "Multiple cursors", action: "Back to one cursor", keys: "Esc or click"),
        ShortcutEntry(category: "Format", action: "Bold", keys: "⌘B"),
        ShortcutEntry(category: "Format", action: "Italic", keys: "⌘I"),
        ShortcutEntry(category: "Format", action: "Link", keys: "⌘K"),
        ShortcutEntry(category: "Format", action: "Heading 1 to 6", keys: "⌥⌘1 to ⌥⌘6"),
        ShortcutEntry(category: "Format", action: "Normal text", keys: "⌥⌘0"),
        ShortcutEntry(category: "Format", action: "Bulleted list", keys: "⇧⌘8"),
        ShortcutEntry(category: "Format", action: "Numbered list", keys: "⇧⌘7"),
        ShortcutEntry(category: "Lines", action: "Duplicate line", keys: "⇧⌘D"),
        ShortcutEntry(category: "Lines", action: "Move line up", keys: "⌥↑"),
        ShortcutEntry(category: "Lines", action: "Move line down", keys: "⌥↓"),
        ShortcutEntry(category: "Lines", action: "Join lines", keys: "⌘J"),
        ShortcutEntry(category: "View", action: "Markdown preview", keys: "⇧⌘P"),
        ShortcutEntry(category: "View", action: "Formatted view", keys: "⇧⌘F"),
        ShortcutEntry(category: "View", action: "Word wrap", keys: "⌥⌘W"),
        ShortcutEntry(category: "View", action: "Line numbers", keys: "⌥⌘L"),
        ShortcutEntry(category: "View", action: "Focus mode", keys: "⇧⌘Return"),
        ShortcutEntry(category: "View", action: "Zoom in", keys: "⌘="),
        ShortcutEntry(category: "View", action: "Zoom out", keys: "⌘-"),
        ShortcutEntry(category: "View", action: "Actual size", keys: "⌘0"),
        ShortcutEntry(category: "View", action: "Zoom with the scroll wheel or trackpad", keys: "⌘ scroll"),
        ShortcutEntry(category: "Tabs", action: "Next tab", keys: "⇧⌘]"),
        ShortcutEntry(category: "Tabs", action: "Previous tab", keys: "⇧⌘["),
        ShortcutEntry(category: "Tabs", action: "Go to tab 1 to 9", keys: "⌘1 to ⌘9"),
        ShortcutEntry(category: "Tabs", action: "Move a tab to its own window", keys: "Drag it out of the tab strip"),
        ShortcutEntry(category: "Settings", action: "Settings", keys: "⌘,"),
    ]

    /// The categories in the order they appear, without repeats.
    public static var categories: [String] {
        var seen = Set<String>()
        return all.map(\.category).filter { seen.insert($0).inserted }
    }

    /// The entries that match a search, by action, category or key text. An empty query matches everything.
    public static func entries(matching query: String) -> [ShortcutEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.action.lowercased().contains(needle) || $0.category.lowercased().contains(needle)
                || $0.keys.lowercased().contains(needle)
        }
    }
}
