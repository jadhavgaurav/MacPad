import NotePadCore
import SwiftUI

/// Lists the saved versions of the active file and previews one, so the user can bring an older version back.
struct VersionHistoryView: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    @Local private var versions: [SavedVersion] = []
    @Local private var selection: SavedVersion.ID?
    @Local private var preview = ""
    @Local private var errorMessage: String?

    private var selectedVersion: SavedVersion? { versions.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version History").font(.headline)
            content
            HStack {
                Spacer()
                Button("Restore") { restoreSelection() }
                    .disabled(selectedVersion == nil)
                    .pointingHandCursor()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
            }
        }
        .padding(20)
        .frame(width: 720, height: 460)
        .onAppear(perform: load)
    }

    @ViewBuilder private var content: some View {
        if state.activeDocument?.fileURL == nil {
            message("Save this tab to a file first. MacPad keeps a copy each time you save it.")
        } else if let errorMessage {
            message(errorMessage)
        } else if versions.isEmpty {
            message("No saved versions yet. MacPad keeps a copy each time you save this file.")
        } else {
            HStack(spacing: 12) {
                List(versions, selection: $selection) { version in
                    // A button, so VoiceOver and other assistive tools can pick a version with one action.
                    Button { selection = version.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.date.formatted(date: .abbreviated, time: .shortened))
                            Text(ByteCountFormatter.string(fromByteCount: Int64(version.byteCount), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .accessibilityLabel("Version saved \(version.date.formatted(date: .abbreviated, time: .shortened))")
                }
                .frame(width: 220)
                .onChange(of: selection) { _, _ in showPreview() }
                ScrollView {
                    Text(preview.isEmpty ? "(empty)" : preview)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
                .accessibilityLabel("Version preview")
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func load() {
        do {
            versions = try state.versionsOfActiveFile()
            selection = versions.first?.id
            showPreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showPreview() {
        guard let version = selectedVersion else {
            preview = ""
            return
        }
        do {
            preview = try state.text(of: version)
        } catch {
            preview = error.localizedDescription
        }
    }

    private func restoreSelection() {
        guard let version = selectedVersion else { return }
        do {
            try state.restore(version)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
