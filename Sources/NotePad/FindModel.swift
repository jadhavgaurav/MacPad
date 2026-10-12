import Foundation
import NotePadCore
import Observation

@MainActor
@Observable
final class FindModel {
    var isVisible = false
    var showsReplace = false
    var query = ""
    var replacement = ""
    var options = FindOptions()
    var focusToken = 0
    private(set) var matches: [NSRange] = []
    private(set) var currentIndex: Int?

    private var state: AppState { AppState.shared }

    var counterText: String {
        if query.isEmpty { return "" }
        if !FindEngine.isValidPattern(query, options: options) { return "Invalid pattern" }
        guard let currentIndex else { return "No results" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    var hasNoResults: Bool { !query.isEmpty && matches.isEmpty }
    var hasInvalidPattern: Bool { !query.isEmpty && !FindEngine.isValidPattern(query, options: options) }

    func show(replace: Bool) {
        isVisible = true
        showsReplace = replace
        if let doc = state.activeDocument, doc.selection.length > 0, doc.selection.length < 200 {
            let selected = (doc.text as NSString).substring(with: doc.selection)
            if !selected.contains("\n") { query = selected }
        }
        focusToken += 1
        refresh(select: !query.isEmpty)
    }

    func hide() {
        isVisible = false
        matches = []
        currentIndex = nil
        state.activeEditor?.setFindHighlights([], current: nil)
        state.activeEditor?.focus()
    }

    /// Recomputes matches. With `select`, jumps to the first match at or after the caret.
    func refresh(select: Bool = false) {
        guard isVisible, let doc = state.activeDocument else {
            matches = []
            currentIndex = nil
            return
        }
        matches = FindEngine.matches(of: query, in: doc.text, options: options)
        currentIndex = FindEngine.indexOfMatch(atOrAfter: doc.selection.location, in: matches)
        if select, let currentIndex { state.activeEditor?.select(matches[currentIndex]) }
        state.activeEditor?.setFindHighlights(matches, current: currentIndex)
    }

    /// What the preview should highlight. Regex and whole-word search are editor-only, because their matches
    /// do not map onto the rendered text.
    var previewHighlight: PreviewFind? {
        guard isVisible, !query.isEmpty, !options.regex, !options.wholeWord else { return nil }
        return PreviewFind(query: query, matchCase: options.matchCase, current: currentIndex)
    }

    func next() { step(by: 1) }
    func previous() { step(by: -1) }

    private func step(by delta: Int) {
        guard !matches.isEmpty else { return }
        let start = currentIndex ?? (delta > 0 ? -1 : 0)
        let index = (start + delta + matches.count) % matches.count
        currentIndex = index
        state.activeEditor?.select(matches[index])
        state.activeEditor?.setFindHighlights(matches, current: index)
    }

    func replaceCurrent() {
        guard let index = currentIndex, matches.indices.contains(index), let editor = state.activeEditor else { return }
        let range = matches[index]
        let text = state.activeDocument?.text ?? ""
        let inserted = FindEngine.replacementText(for: range, in: text, query: query, replacement: replacement, options: options)
        editor.replaceCharacters(in: range, with: inserted)
        editor.select(NSRange(location: range.location + (inserted as NSString).length, length: 0), scrollToVisible: false)
        refresh(select: true)
    }

    func replaceAll() {
        guard let doc = state.activeDocument, let editor = state.activeEditor else { return }
        let result = FindEngine.replacingAll(query, with: replacement, in: doc.text, options: options)
        guard result.count > 0 else { return }
        editor.replaceWholeText(result.text)
        state.showNotice(result.count == 1 ? "Replaced 1 match." : "Replaced \(result.count) matches.")
        refresh()
    }
}
