import MacPadCore
import SwiftUI

struct StatusBarView: View {
    let state: AppState

    var body: some View {
        if let doc = state.activeDocument {
            let counts = state.stats.selectionStats ?? state.stats.stats
            let prefix = state.stats.selectionStats == nil ? "" : "Selected "
            HStack(spacing: 2) {
                Button { state.gotoVisible = true } label: {
                    cell("Ln \(state.stats.position.line), Col \(state.stats.position.column)")
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Go to line (\u{2318}L)")
                .popover(isPresented: Binding(get: { state.gotoVisible }, set: { state.gotoVisible = $0 }), arrowEdge: .top) {
                    GoToLineView(state: state)
                }
                separator
                cell("\(prefix)Lines \(counts.lines.formatted())")
                cell("\(prefix)Words \(counts.words.formatted())")
                cell("\(TextStats.readingMinutes(words: counts.words)) min read")
                cell("\(prefix)Chars \(counts.characters.formatted())")
                cell("\(prefix)No spaces \(counts.charactersWithoutSpaces.formatted())")
                separator
                lineNumbersToggle
                separator
                zoomMenu(doc)
                lineEndingMenu(doc)
                encodingMenu(doc)
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .glassCapsule()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Status bar")
        }
    }

    private func cell(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 3).lineLimit(1).fixedSize()
    }

    /// Footer toggle for the line-number gutter. Highlighted while the gutter is shown.
    private var lineNumbersToggle: some View {
        Button { state.showLineNumbers.toggle() } label: {
            Image(systemName: "list.number")
                .foregroundStyle(state.showLineNumbers ? Color.accentColor : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(state.showLineNumbers ? "Hide line numbers" : "Show line numbers")
        .accessibilityLabel("Line numbers")
        .accessibilityValue(state.showLineNumbers ? "On" : "Off")
        .accessibilityAddTraits(state.showLineNumbers ? .isSelected : [])
    }

    private var separator: some View {
        Rectangle().fill(.quaternary).frame(width: 1, height: 12).padding(.horizontal, 4)
    }

    private func zoomMenu(_ doc: TextDocument) -> some View {
        Menu {
            ForEach([50, 75, 100, 125, 150, 200], id: \.self) { percent in
                Button("\(percent)%") { doc.zoom = Double(percent) / 100 }
            }
        } label: { cell("\(Int((doc.zoom * 100).rounded()))%") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .pointingHandCursor()
            .accessibilityLabel("Zoom")
    }

    private func lineEndingMenu(_ doc: TextDocument) -> some View {
        Menu {
            ForEach(LineEnding.allCases, id: \.self) { ending in
                Button(ending.label) { state.setLineEnding(ending, for: doc) }
            }
        } label: { cell(doc.lineEnding.label) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .pointingHandCursor()
            .accessibilityLabel("Line ending, \(doc.lineEnding.label)")
    }

    private func encodingMenu(_ doc: TextDocument) -> some View {
        Menu {
            if doc.fileURL != nil {
                Section("Reopen with Encoding") {
                    ForEach(TextEncoding.allCases, id: \.self) { encoding in
                        Button(encoding.label) { state.reopen(doc, as: encoding) }
                    }
                }
            }
            Section("Save with Encoding") {
                ForEach(TextEncoding.allCases, id: \.self) { encoding in
                    Button(encoding.label) { state.setEncoding(encoding, for: doc) }
                }
            }
        } label: { cell(doc.encoding.label) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .pointingHandCursor()
            .accessibilityLabel("Encoding, \(doc.encoding.label)")
    }
}

struct GoToLineView: View {
    let state: AppState
    @Local private var text = ""
    @Local private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Go to line").font(.headline)
            TextField("Line number", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: text) { error = nil }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(16)
        .onAppear {
            // Popovers take focus after they appear, so claim it on the next run loop turn.
            DispatchQueue.main.async { isFocused = true }
        }
    }

    private func commit() {
        let total = LineLocator.lineCount(in: state.activeDocument?.text ?? "")
        guard let line = Int(text.trimmingCharacters(in: .whitespaces)), (1...total).contains(line) else {
            error = "Enter a line from 1 to \(total.formatted())."
            return
        }
        if state.goTo(line: line) { state.gotoVisible = false }
    }
}
