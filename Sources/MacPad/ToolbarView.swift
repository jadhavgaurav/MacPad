import MacPadCore
import SwiftUI

/// Formatting and view controls, mirroring the Windows 11 Notepad toolbar.
struct ToolbarView: View {
    let state: AppState
    let formatAllText: Bool
    let wrapByDefault: Bool

    var body: some View {
        let doc = state.activeDocument
        let formatted = doc?.usesFormattedView(formatAllText: formatAllText) ?? false
        HStack(spacing: 2) {
            Menu {
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { state.format(.heading(level)) }
                }
                Divider()
                Button("Normal Text") { state.format(.clearHeading) }
            } label: {
                Text("H1").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            .menuIndicator(.visible)
            .help("Heading")
            .accessibilityLabel("Heading")
            .frame(width: 46, height: 28)
            .pointingHandCursor()

            Menu {
                Button("Bulleted List") { state.format(.bulletList) }
                Button("Numbered List") { state.format(.numberedList) }
            } label: {
                Image(systemName: "list.bullet").foregroundStyle(.secondary)
            }
            .menuIndicator(.visible)
            .help("List")
            .accessibilityLabel("List")
            .frame(width: 46, height: 28)
            .pointingHandCursor()

            iconButton("bold", help: "Bold (\u{2318}B)") { state.format(.bold) }
            iconButton("italic", help: "Italic (\u{2318}I)") { state.format(.italic) }
            iconButton("link", help: "Link (\u{2318}K)") { state.format(.link(url: nil)) }

            divider
            iconButton(
                "textformat",
                help: formatted ? "Show raw Markdown" : "Show formatted text",
                label: "Formatted text",
                isOn: formatted
            ) {
                state.toggleFormattedView()
            }
            iconButton("sidebar.right", help: "Markdown preview", isOn: doc?.previewVisible ?? false) {
                state.togglePreview()
            }
            iconButton("magnifyingglass", help: "Find (\u{2318}F)") { state.find.show(replace: false) }
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .padding(4)
        .frame(height: 38)
        .glassCapsule()
    }

    private var divider: some View {
        Rectangle().fill(.quaternary).frame(width: 1, height: 16).padding(.horizontal, 2)
    }

    private func iconButton(
        _ symbol: String, help: String, label: String? = nil, isOn: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .background(Circle().fill(isOn ? Color.accentColor.opacity(0.16) : .clear))
                .pointingHandCursor()
        }
        .help(help)
        .accessibilityLabel(label ?? help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
