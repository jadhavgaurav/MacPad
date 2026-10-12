import AppKit
import NotePadCore

/// A text view that pastes plain text only, so formatting from other apps never leaks into a .txt file.
final class PlainTextView: NSTextView {
    /// Receives the zoom factor for a Command + scroll gesture.
    var onCommandScroll: ((CGFloat) -> Void)?

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    /// The offset where an Option-drag column selection started. Nil when no column drag is in progress.
    private var columnAnchor: Int?

    /// NSTextView draws only the primary insertion point, so the extra carets are drawn here.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let ranges = currentRanges
        guard ranges.count > 1, let window else { return }
        insertionPointColor.setFill()
        for caret in ranges where caret.length == 0 {
            let screenRect = firstRect(forCharacterRange: caret, actualRange: nil)
            let local = convert(window.convertFromScreen(screenRect), from: nil)
            NSRect(x: local.minX, y: local.minY, width: 2, height: local.height).fill()
        }
    }

    /// Sets every caret and selection. NSTextView's selectedRanges setter drops extra zero-length carets under
    /// TextKit 2, so several carets are set as text selections instead.
    func setCarets(_ ranges: [NSRange]) {
        guard ranges.count > 1, let layout = textLayoutManager, let content = layout.textContentManager else {
            setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
            return
        }
        let selections: [NSTextSelection] = ranges.compactMap { range in
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { return nil }
            return NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)
        }
        layout.textSelections = selections
        needsDisplay = true
    }

    /// Every caret and selection. `selectedRanges` reports only the primary one when several carets exist,
    /// so the text selections of the layout manager are read directly.
    var currentRanges: [NSRange] {
        guard let layout = textLayoutManager, let content = layout.textContentManager, layout.textSelections.count > 1 else {
            return selectedRanges.map { $0.rangeValue }
        }
        return layout.textSelections.flatMap { $0.textRanges }.map { textRange in
            let start = content.offset(from: content.documentRange.location, to: textRange.location)
            return NSRange(location: start, length: content.offset(from: textRange.location, to: textRange.endLocation))
        }
    }

    /// Option-click adds a caret where it lands, or removes the one already there. Shift-Option-drag makes a column selection.
    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags
        guard flags.contains(.option), event.clickCount == 1 else {
            // A normal click drops every extra caret, as in VS Code, then behaves as usual.
            if currentRanges.count > 1 {
                collapseCarets(to: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)))
            }
            super.mouseDown(with: event)
            return
        }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        guard flags.contains(.shift) else {
            let carets = MultiCursor.togglingCaret(at: index, in: currentRanges)
            setCarets(carets)
            return
        }
        columnAnchor = index
        setSelectedRange(NSRange(location: index, length: 0))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = columnAnchor else {
            super.mouseDragged(with: event)
            return
        }
        let head = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let ranges = MultiCursor.columnSelection(anchor: anchor, head: head, in: string)
        setCarets(ranges)
    }

    override func mouseUp(with event: NSEvent) {
        if columnAnchor != nil {
            columnAnchor = nil
            return
        }
        super.mouseUp(with: event)
    }

    /// Typing replaces every selection, so one keystroke edits each caret.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard currentRanges.count > 1, let text = string as? String else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        applyMultiEdit(MultiCursor.insert(text, at: currentRanges, in: self.string))
    }

    override func insertNewline(_ sender: Any?) {
        guard currentRanges.count > 1 else {
            super.insertNewline(sender)
            return
        }
        applyMultiEdit(MultiCursor.insert("\n", at: currentRanges, in: string))
    }

    override func deleteForward(_ sender: Any?) {
        guard currentRanges.count > 1 else {
            super.deleteForward(sender)
            return
        }
        applyMultiEdit(MultiCursor.deleteForward(at: currentRanges, in: string))
    }

    override func insertTab(_ sender: Any?) {
        guard currentRanges.count > 1 else {
            super.insertTab(sender)
            return
        }
        applyMultiEdit(MultiCursor.insert("\t", at: currentRanges, in: string))
    }

    override func deleteBackward(_ sender: Any?) {
        guard currentRanges.count > 1 else {
            super.deleteBackward(sender)
            return
        }
        applyMultiEdit(MultiCursor.deleteBackward(at: currentRanges, in: string))
    }

    /// Escape drops back to a single caret, placed at the most recent selection.
    override func cancelOperation(_ sender: Any?) {
        guard currentRanges.count > 1, let last = currentRanges.last else {
            super.cancelOperation(sender)
            return
        }
        collapseCarets(to: NSMaxRange(last))
    }

    /// Leaves one caret at `index`. The layout manager's extra text selections are cleared first,
    /// because setting selectedRanges alone does not remove them.
    func collapseCarets(to index: Int) {
        textLayoutManager?.textSelections = []
        setSelectedRange(NSRange(location: index, length: 0))
        needsDisplay = true
    }

    /// Applies a multi-cursor edit as one undo step and restores every caret.
    private func applyMultiEdit(_ edit: MultiCursor.Edit) {
        let change = MinimalEdit(from: string, to: edit.text)
        if !change.isNoOp, shouldChangeText(in: change.range, replacementString: change.replacement) {
            textStorage?.replaceCharacters(in: change.range, with: change.replacement)
            didChangeText()
        }
        setCarets(edit.selections)
    }

    /// Adds a caret on the line above or below, at the same column. Repeating it keeps stacking.
    func addCaret(_ direction: MultiCursor.VerticalDirection) {
        guard let carets = MultiCursor.addingCaret(direction, to: currentRanges, in: string) else {
            NSSound.beep()
            return
        }
        setCarets(carets)
        if let added = carets.last { scrollRangeToVisible(added) }
    }

    /// Adds the next match of the current selection. With only carets, it first selects the word at the caret.
    func addNextOccurrence() {
        let ranges = currentRanges
        guard ranges.contains(where: { $0.length > 0 }) else {
            guard let caret = ranges.last else { return }
            let word = selectionRange(forProposedRange: caret, granularity: .selectByWord)
            guard word.length > 0 else {
                NSSound.beep()
                return
            }
            setSelectedRange(word)
            return
        }
        guard let next = MultiCursor.nextOccurrence(in: string, selections: ranges) else {
            NSSound.beep()
            return
        }
        setCarets((ranges + [next]))
        scrollRangeToVisible(next)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let onCommandScroll else {
            super.scrollWheel(with: event)
            return
        }
        // Trackpads report small precise deltas; mouse wheels report larger, coarser steps.
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.004 : event.scrollingDeltaY * 0.03
        guard step != 0 else { return }
        // Each event changes the zoom by at most 10%, so a fast flick stays controllable.
        onCommandScroll(min(max(1 + step, 0.9), 1.1))
    }
}
