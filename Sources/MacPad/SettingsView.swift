import AppKit
import MacPadCore
import SwiftUI

/// The panes of the Settings window. The raw value is stored, so a menu item can open a pane directly.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case shortcuts

    var id: String { rawValue }
}

@MainActor
enum SettingsNavigation {
    static let paneKey = "settings.pane"

    /// Opens the Settings window on a pane.
    static func open(_ pane: SettingsPane) {
        UserDefaults.standard.set(pane.rawValue, forKey: paneKey)
        NSApp.activate(ignoringOtherApps: true)
        AppState.shared.openSettingsAction?()
    }
}

struct SettingsView: View {
    @AppStorage(SettingsNavigation.paneKey) private var pane = SettingsPane.general.rawValue

    var body: some View {
        TabView(selection: $pane) {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsPane.general.rawValue)
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsPane.shortcuts.rawValue)
        }
        .frame(width: 600, height: 500)
    }
}

private struct GeneralSettingsPane: View {
    @AppStorage(SettingsKey.fontName) private var fontName = EditorSettings.systemMono
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.wrapByDefault) private var wrapByDefault = true
    @AppStorage(SettingsKey.formatAllText) private var formatAllText = false

    private let families = EditorSettings.fixedPitchFamilies

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font", selection: $fontName) {
                    ForEach(families, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: $fontSize, in: 9...32, step: 1) {
                    Text("Size: \(Int(fontSize)) pt")
                }
                Toggle("Wrap long lines by default", isOn: $wrapByDefault)
            }
            Section("Formatting") {
                Toggle("Style Markdown in all text files", isOn: $formatAllText)
                Text("Markdown files are always styled. Turn this on to style plain text files too.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

private struct ShortcutsSettingsPane: View {
    @Local private var query = ""

    var body: some View {
        let matches = ShortcutCatalog.entries(matching: query)
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search shortcuts", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search shortcuts")
            if matches.isEmpty {
                Spacer()
                Text("No shortcut matches \u{201C}\(query)\u{201D}.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(ShortcutCatalog.categories, id: \.self) { category in
                        let rows = matches.filter { $0.category == category }
                        if !rows.isEmpty {
                            Section(category) {
                                ForEach(rows) { entry in
                                    HStack {
                                        Text(entry.action)
                                        Spacer()
                                        KeyCap(text: entry.keys)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

/// A key or gesture shown as a keycap.
private struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
            .foregroundStyle(.primary)
    }
}
