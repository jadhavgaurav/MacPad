import AppKit

enum SettingsKey {
    static let fontName = "editor.fontName"
    static let fontSize = "editor.fontSize"
    static let wrapByDefault = "editor.wrapByDefault"
    static let formatAllText = "editor.formatAllText"
    static let showLineNumbers = "editor.showLineNumbers"
}

struct EditorSettings: Equatable {
    static let systemMono = "System Mono"

    var fontName = EditorSettings.systemMono
    var fontSize = 13.0
    var wrapByDefault = true
    var formatAllText = false

    static func current() -> EditorSettings {
        let defaults = UserDefaults.standard
        return EditorSettings(
            fontName: defaults.string(forKey: SettingsKey.fontName) ?? systemMono,
            fontSize: defaults.object(forKey: SettingsKey.fontSize) as? Double ?? 13,
            wrapByDefault: defaults.object(forKey: SettingsKey.wrapByDefault) as? Bool ?? true,
            formatAllText: defaults.bool(forKey: SettingsKey.formatAllText)
        )
    }

    func font(zoom: Double) -> NSFont {
        let size = max(6, fontSize * zoom)
        if fontName != Self.systemMono, let font = NSFont(name: fontName, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var fixedPitchFamilies: [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        return [systemMono] + families.sorted()
    }
}
