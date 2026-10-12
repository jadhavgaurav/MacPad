import NotePadCore
import SwiftUI

struct NotePadCommands: Commands {
    private var state: AppState { AppState.shared }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { state.newTab() }.keyboardShortcut("n")
            Button("Open\u{2026}") { state.presentOpenPanel() }.keyboardShortcut("o")
            Divider()
            Button("Share\u{2026}") { state.shareActive() }
            Divider()
            Button("Export as HTML\u{2026}") { state.exportActive(asPDF: false) }
            Button("Export as PDF\u{2026}") { state.exportActive(asPDF: true) }
            Button("Move Tab to New Window") { if let id = state.activeID { state.moveToNewWindow(id) } }
                .disabled(state.activeDocument == nil)
            Button("Version History\u{2026}") { state.historyVisible = true }
                .disabled(state.activeDocument?.fileURL == nil)
            Button("Recover Set-Aside Tabs\u{2026}") { state.recoveryVisible = true }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") { if let id = state.activeID { state.closeTab(id) } }.keyboardShortcut("w")
            Divider()
            Button("Save") { if let doc = state.activeDocument { state.save(doc) } }.keyboardShortcut("s")
            Button("Save As\u{2026}") { if let doc = state.activeDocument { state.saveAs(doc) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Add Next Occurrence") { state.activeEditor?.addNextOccurrence() }.keyboardShortcut("d")
            Button("Add Cursor Above") { state.activeEditor?.addCaret(.up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Add Cursor Below") { state.activeEditor?.addCaret(.down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button("Find\u{2026}") { state.find.show(replace: false) }.keyboardShortcut("f")
            Button("Find and Replace\u{2026}") { state.find.show(replace: true) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find Next") { state.find.next() }.keyboardShortcut("g")
            Button("Find Previous") { state.find.previous() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Go to Line\u{2026}") { state.gotoVisible = true }.keyboardShortcut("l")
        }
        CommandMenu("Format") {
            Button("Bold") { state.format(.bold) }.keyboardShortcut("b")
            Button("Italic") { state.format(.italic) }.keyboardShortcut("i")
            Button("Link\u{2026}") { state.format(.link(url: nil)) }.keyboardShortcut("k")
            Divider()
            ForEach(1...6, id: \.self) { level in
                Button("Heading \(level)") { state.format(.heading(level)) }
                    .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: [.command, .option])
            }
            Button("Normal Text") { state.format(.clearHeading) }.keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Button("Bulleted List") { state.format(.bulletList) }.keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { state.format(.numberedList) }.keyboardShortcut("7", modifiers: [.command, .shift])
            Divider()
            Button("Duplicate Line") { state.lineCommand(LineEditor.duplicate) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Move Line Up") { state.lineCommand(LineEditor.moveUp) }.keyboardShortcut(.upArrow, modifiers: .option)
            Button("Move Line Down") { state.lineCommand(LineEditor.moveDown) }.keyboardShortcut(.downArrow, modifiers: .option)
            Button("Join Lines") { state.lineCommand(LineEditor.join) }.keyboardShortcut("j", modifiers: .command)
            Button("Sort Lines") { state.lineCommand(LineEditor.sort) }
            Button("Remove Duplicate Lines") { state.lineCommand(LineEditor.removeDuplicates) }
        }
        CommandMenu("Snippets") {
            Menu("Templates") {
                ForEach(SnippetStore.builtIn) { snippet in
                    Button(snippet.name) { state.insertSnippet(snippet) }
                }
            }
            Menu("My Snippets") {
                ForEach(state.snippets.userSnippets) { snippet in
                    Button(snippet.name) { state.insertSnippet(snippet) }
                }
            }
            .disabled(state.snippets.userSnippets.isEmpty)
            Divider()
            Button("Save Selection as Snippet\u{2026}") { state.saveSelectionAsSnippet() }
            Menu("Delete Snippet") {
                ForEach(state.snippets.userSnippets) { snippet in
                    Button(snippet.name) { state.deleteSnippet(snippet) }
                }
            }
            .disabled(state.snippets.userSnippets.isEmpty)
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In") { state.zoom(by: 1.1) }.keyboardShortcut("=")
            Button("Zoom Out") { state.zoom(by: 1 / 1.1) }.keyboardShortcut("-")
            Button("Actual Size") { state.resetZoom() }.keyboardShortcut("0")
            Divider()
            Button("Toggle Word Wrap") { state.toggleWordWrap() }.keyboardShortcut("w", modifiers: [.command, .option])
            Button("Toggle Formatted View") { state.toggleFormattedView() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Toggle Markdown Preview") { state.togglePreview() }.keyboardShortcut("p", modifiers: [.command, .shift])
            Button(state.focusMode ? "Exit Focus Mode" : "Focus Mode") { state.toggleFocusMode() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Button(state.showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers") { state.showLineNumbers.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .option])
        }
        CommandGroup(after: .windowArrangement) {
            Divider()
            Button("Show Next Tab") { state.cycleTab(by: 1) }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Tab") { state.cycleTab(by: -1) }.keyboardShortcut("[", modifiers: [.command, .shift])
            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") { state.selectTab(number: number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
        }
    }
}
