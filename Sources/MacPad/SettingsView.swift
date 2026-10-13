import SwiftUI

struct SettingsView: View {
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
        .frame(width: 440, height: 320)
    }
}
