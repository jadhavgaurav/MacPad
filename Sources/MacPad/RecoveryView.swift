import MacPadCore
import SwiftUI

/// Lists session files that were set aside at launch, so the user can get their text back.
struct RecoveryView: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss
    @Local private var files: [SessionStore.QuarantinedFile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recover set-aside tabs").font(.headline)
            if files.isEmpty {
                Text("Nothing was set aside. Every saved tab opened normally.")
                    .foregroundStyle(.secondary)
            } else {
                Text("These tabs could not be read when MacPad opened. Recovering one opens its text in a new tab.")
                    .font(.callout).foregroundStyle(.secondary)
                List(files) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(file.setAside.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(file.preview.isEmpty ? "(empty)" : file.preview)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(3)
                        HStack {
                            Button("Recover") {
                                state.recover(file)
                                files = state.setAsideFiles()
                            }
                            .pointingHandCursor()
                            Button("Discard", role: .destructive) {
                                state.discard(file)
                                files = state.setAsideFiles()
                            }
                            .pointingHandCursor()
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 260)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .pointingHandCursor()
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear { files = state.setAsideFiles() }
    }
}
