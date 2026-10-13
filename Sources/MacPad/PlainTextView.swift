import AppKit
import MacPadCore

/// A text view that pastes plain text only, so formatting from other apps never leaks into a .txt file.
/// It also supports VS Code-style multiple carets.
///
/// NSTextView has a single insertion point and keeps a private selection that it restores from many places
/// (typing attributes, marked text, undo). So the carets live in `carets`, NSTextView's own selection always
/// equals the primary caret, and this view draws the others and applies edits and moves at each of them.
final class PlainTextView: NSTextView {
    /// Receives the zoom factor for a Command + scroll gesture.
    var onCommandScroll: ((CGFloat) -> Void)?

    /// Every caret while there are two or more, with the primary last. Empty for a single caret, which then
    /// lives only in NSTextView's own selection.
    private(set) var carets: [NSRange] = []
    /// True while this view itself changes the selection or text, so those changes keep the extra carets.
    private var isUpdatingCarets = false
    /// The plain style for text typed at several carets. Using the primary caret's typing attributes would give
    /// every caret the primary's heading or bold style, and lines would jump in height until the next restyle.
    var plainTextAttributes: [NSAttributedString.Key: Any]?
    /// One blinking indicator per extra empty caret. The primary uses NSTextView's own insertion point.
    private var indicators: [NSTextInsertionIndicator] = []
    /// The offset where a Shift-Option-drag column selection started. Nil when no column drag is in progress.
    private var columnAnchor: Int?

    var hasExtraCarets: Bool { carets.count > 1 }

    /// Every caret and selection, with the primary last.
    var currentRanges: [NSRange] { hasExtraCarets ? carets : selectedRanges.map { $0.rangeValue } }

    // MARK: Caret model

    /// Replaces every caret. `primary` is the index of the primary caret in `ranges` (the last one by default).
    /// Overlapping carets merge. NSTextView's selection is set to the primary, which posts the usual
    /// selection-change notification.
    func setCarets(_ ranges: [NSRange], primary: Int? = nil) {
        let length = (string as NSString).length
        let valid = ranges.map { range -> NSRange in
            let location = min(max(range.location, 0), length)
            return NSRange(location: location, length: min(range.length, length - location))
        }
        let normalized = MultiCursor.normalized(valid, primary: primary ?? valid.count - 1)
        guard let primaryRange = normalized.last else { return }
        carets = normalized.count > 1 ? normalized : []
        isUpdatingCarets = true
        super.setSelectedRanges([NSValue(range: primaryRange)], affinity: .downstream, stillSelecting: false)
        isUpdatingCarets = false
        refreshCaretDisplay()
    }

    /// NSTextView moved the selection on its own (a click, an arrow key without extra carets, undo, or a command
    /// this view does not handle), so the extra carets no longer apply.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        if !isUpdatingCarets, hasExtraCarets, ranges.map({ $0.rangeValue }) != [carets[carets.count - 1]] {
            carets = []
            refreshCaretDisplay()
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    /// Text changed by something other than a multi-caret edit, so the extra carets' offsets are stale.
    override func didChangeText() {
        if !isUpdatingCarets, hasExtraCarets {
            carets = []
            refreshCaretDisplay()
        }
        super.didChangeText()
    }

    // MARK: Drawing the extra carets

    /// Places one insertion indicator per extra empty caret and redraws the extra selection highlights.
    /// `active` overrides the focus check while first-responder status is changing.
    func refreshCaretDisplay(active: Bool? = nil) {
        positionIndicators(active: active)
        needsDisplay = true
        // TextKit 2 lays out changed lines lazily, so the positions are checked again once that layout has run.
        // (NSTextView's own layout-pass hook is public only in the macOS 27 SDK, which older build machines lack.)
        if hasExtraCarets {
            DispatchQueue.main.async { [weak self] in self?.positionIndicators() }
        }
    }

    /// Moves the indicators onto the extra empty carets, adding or removing indicators as needed.
    private func positionIndicators(active: Bool? = nil) {
        let extras = hasExtraCarets ? Array(carets.dropLast()) : []
        let rects = extras.filter { $0.length == 0 }.compactMap(caretRect(for:))
        while indicators.count > rects.count { indicators.removeLast().removeFromSuperview() }
        while indicators.count < rects.count {
            let indicator = NSTextInsertionIndicator(frame: .zero)
            addSubview(indicator)
            indicators.append(indicator)
        }
        let isActive = active ?? (window?.isKeyWindow == true && window?.firstResponder === self)
        for (indicator, rect) in zip(indicators, rects) {
            if indicator.frame != rect { indicator.frame = rect }
            indicator.color = insertionPointColor
            indicator.displayMode = isActive ? .automatic : .hidden
        }
    }

    /// NSTextView highlights only the primary selection, so the other non-empty selections are filled here,
    /// behind the text.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hasExtraCarets else { return }
        let isActive = window?.isKeyWindow == true && window?.firstResponder === self
        (isActive ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor).setFill()
        for range in carets.dropLast() where range.length > 0 {
            for rect in selectionRects(for: range) where rect.intersects(dirtyRect) { rect.fill() }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        refreshCaretDisplay(active: accepted)
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { refreshCaretDisplay(active: false) }
        return resigned
    }

    /// Wrapping, zoom and window resizes move the text, so the indicators follow.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if hasExtraCarets { refreshCaretDisplay() }
    }

    /// The caret's frame in view coordinates, taken from TextKit 2 after laying out its line, so it matches
    /// styled text, wrapped lines and line spacing exactly as NSTextView draws its own caret.
    private func caretRect(for caret: NSRange) -> NSRect? {
        guard let layout = textLayoutManager, let textRange = textRange(for: caret) else { return nil }
        layout.ensureLayout(for: textRange)
        var segment: NSRect?
        layout.enumerateTextSegments(in: textRange, type: .selection, options: [.rangeNotRequired]) { _, frame, _, _ in
            segment = frame
            return false
        }
        guard let frame = segment else { return nil }
        let origin = textContainerOrigin
        return NSRect(x: frame.minX + origin.x, y: frame.minY + origin.y, width: 2, height: frame.height)
    }

    private func selectionRects(for range: NSRange) -> [NSRect] {
        guard let layout = textLayoutManager, let textRange = textRange(for: range) else { return [] }
        let origin = textContainerOrigin
        var rects: [NSRect] = []
        layout.enumerateTextSegments(in: textRange, type: .selection, options: []) { _, frame, _, _ in
            rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return rects
    }

    func textRange(for range: NSRange) -> NSTextRange? {
        guard let content = textLayoutManager?.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    func range(for textRange: NSTextRange) -> NSRange {
        guard let content = textLayoutManager?.textContentManager else { return NSRange(location: 0, length: 0) }
        let start = content.offset(from: content.documentRange.location, to: textRange.location)
        return NSRange(location: start, length: content.offset(from: textRange.location, to: textRange.endLocation))
    }

    // MARK: Mouse

    /// Option-click adds a caret where it lands, or removes the one already there, whatever the click count.
    /// Shift-Option-drag makes a column selection. A normal click drops the extra carets, as in VS Code.
    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags
        guard flags.contains(.option) else {
            if hasExtraCarets {
                setCarets([NSRange(location: characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)), length: 0)])
            }
            super.mouseDown(with: event)
            return
        }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if flags.contains(.shift) {
            columnAnchor = index
            setCarets([NSRange(location: index, length: 0)])
        } else {
            setCarets(MultiCursor.togglingCaret(at: index, in: currentRanges))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = columnAnchor else {
            super.mouseDragged(with: event)
            return
        }
        autoscroll(with: event)
        let head = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        setCarets(MultiCursor.columnSelection(anchor: anchor, head: head, in: string))
    }

    override func mouseUp(with event: NSEvent) {
        if columnAnchor != nil {
            columnAnchor = nil
            return
        }
        super.mouseUp(with: event)
    }

    // MARK: Typing and commands

    override func paste(_ sender: Any?) {
        guard hasExtraCarets, let text = NSPasteboard.general.string(forType: .string) else {
            pasteAsPlainText(sender)
            return
        }
        // As in VS Code: when the clipboard holds one line per caret, each caret gets its own line.
        var lines = text.components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        let order = carets.indices.sorted { carets[$0].location < carets[$1].location }
        var pieces = Array(repeating: text, count: carets.count)
        if lines.count == carets.count {
            for (line, index) in zip(lines, order) { pieces[index] = line }
        }
        applyMultiEdit(zip(carets, pieces).map { ($0, $1) })
    }

    override func copy(_ sender: Any?) {
        guard hasExtraCarets else {
            super.copy(sender)
            return
        }
        let ns = string as NSString
        let pieces = carets.sorted { $0.location < $1.location }.filter { $0.length > 0 }.map { ns.substring(with: $0) }
        guard !pieces.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pieces.joined(separator: "\n"), forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard hasExtraCarets else {
            super.cut(sender)
            return
        }
        copy(sender)
        applyMultiEdit(carets.map { ($0, "") })
    }

    /// Typing replaces every selection, so one keystroke edits each caret. An input method that replaces text
    /// before the caret (the press-and-hold accent picker swaps "e" for "é") does the same at every caret.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard hasExtraCarets, !hasMarkedText(), let primary = carets.last,
              let text = (string as? String) ?? (string as? NSAttributedString)?.string else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        guard replacementRange.location != NSNotFound else {
            applyMultiEdit(carets.map { ($0, text) })
            return
        }
        let length = (self.string as NSString).length
        let back = primary.location - replacementRange.location
        applyMultiEdit(carets.map { caret in
            let start = min(max(caret.location - back, 0), length)
            return (NSRange(location: start, length: min(replacementRange.length, length - start)), text)
        })
    }

    /// Composed input (dead keys, CJK input methods) works at the primary caret only.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if hasExtraCarets, let primary = carets.last { setCarets([primary]) }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func doCommand(by selector: Selector) {
        guard hasExtraCarets else {
            super.doCommand(by: selector)
            return
        }
        if let movement = CaretCommand.movements[selector] {
            moveCarets(movement)
        } else if let deletion = CaretCommand.deletions[selector] {
            deleteAtCarets(deletion)
        } else if CaretCommand.newlines.contains(selector) {
            applyMultiEdit(carets.map { ($0, "\n") })
        } else if CaretCommand.tabs.contains(selector) {
            applyMultiEdit(carets.map { ($0, "\t") })
        } else if selector == #selector(cancelOperation(_:)) {
            collapseToPrimary()
        } else if selector == CaretCommand.noop {
            // A key with no binding does nothing, so every caret stays.
            super.doCommand(by: selector)
        } else {
            // Anything else acts on the primary caret only, as NSTextView would.
            collapseToPrimary()
            super.doCommand(by: selector)
        }
    }

    /// Escape drops back to the primary caret.
    override func cancelOperation(_ sender: Any?) {
        guard hasExtraCarets else {
            super.cancelOperation(sender)
            return
        }
        collapseToPrimary()
    }

    private func collapseToPrimary() {
        if let primary = carets.last { setCarets([primary]) }
    }

    private func moveCarets(_ movement: CaretCommand.Movement) {
        guard let navigation = textLayoutManager?.textSelectionNavigation else { return }
        let moved = carets.map { caret -> NSRange in
            guard let textRange = textRange(for: caret),
                  let destination = navigation.destinationSelection(
                      for: NSTextSelection(range: textRange, affinity: .downstream, granularity: .character),
                      direction: movement.direction, destination: movement.destination,
                      extending: movement.extending, confined: false
                  ),
                  let first = destination.textRanges.first else { return caret }
            let ranges = destination.textRanges.map(range(for:))
            return ranges.dropFirst().reduce(range(for: first)) { NSUnionRange($0, $1) }
        }
        setCarets(moved)
        if let primary = carets.last ?? moved.last { scrollRangeToVisible(primary) }
    }

    private func deleteAtCarets(_ deletion: CaretCommand.Deletion) {
        guard let navigation = textLayoutManager?.textSelectionNavigation else { return }
        applyMultiEdit(carets.map { caret in
            guard caret.length == 0, let textRange = textRange(for: caret) else { return (caret, "") }
            let ranges = navigation.deletionRanges(
                for: NSTextSelection(range: textRange, affinity: .downstream, granularity: .character),
                direction: deletion.direction, destination: deletion.destination,
                allowsDecomposition: deletion.decomposes
            ).map(range(for:))
            guard let first = ranges.first else { return (caret, "") }
            return (ranges.dropFirst().reduce(first) { NSUnionRange($0, $1) }, "")
        })
    }

    /// Applies one replacement per caret as a single undo step. Each change is written on its own, so the text
    /// between carets is never rewritten, then every caret is restored.
    private func applyMultiEdit(_ spans: [(range: NSRange, with: String)]) {
        let edit = MultiCursor.replace(spans, in: string)
        guard !edit.changes.isEmpty else {
            setCarets(edit.selections)
            return
        }
        isUpdatingCarets = true
        defer { isUpdatingCarets = false }
        let ranges = edit.changes.map { NSValue(range: $0.range) }
        guard shouldChangeText(inRanges: ranges, replacementStrings: edit.changes.map(\.replacement)),
              let storage = textStorage else { return }
        storage.beginEditing()
        for change in edit.changes.reversed() {
            let attributes = plainTextAttributes ?? typingAttributes
            storage.replaceCharacters(in: change.range, with: NSAttributedString(string: change.replacement, attributes: attributes))
        }
        storage.endEditing()
        didChangeText()
        setCarets(edit.selections)
        if let primary = carets.last ?? edit.selections.last { scrollRangeToVisible(primary) }
    }

    // MARK: Adding carets from the keyboard

    /// Adds a caret on the line above or below, at the same column. Repeating it keeps stacking.
    func addCaret(_ direction: MultiCursor.VerticalDirection) {
        guard let next = MultiCursor.addingCaret(direction, to: currentRanges, in: string) else {
            NSSound.beep()
            return
        }
        setCarets(next)
        if let added = next.last { scrollRangeToVisible(added) }
    }

    /// Adds the next match of the primary selection. With only carets, it first selects the word at every caret.
    func addNextOccurrence() {
        let ranges = currentRanges
        guard ranges.contains(where: { $0.length > 0 }) else {
            let words = ranges.map { selectionRange(forProposedRange: $0, granularity: .selectByWord) }
            guard words.contains(where: { $0.length > 0 }) else {
                NSSound.beep()
                return
            }
            setCarets(words)
            return
        }
        guard let next = MultiCursor.nextOccurrence(in: string, selections: ranges) else {
            NSSound.beep()
            return
        }
        setCarets(ranges + [next])
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

/// The NSTextView commands that act at every caret, mapped onto TextKit 2 selection navigation.
enum CaretCommand {
    struct Movement {
        let direction: NSTextSelectionNavigation.Direction
        let destination: NSTextSelectionNavigation.Destination
        let extending: Bool
    }

    struct Deletion {
        let direction: NSTextSelectionNavigation.Direction
        let destination: NSTextSelectionNavigation.Destination
        let decomposes: Bool
    }

    static let movements: [Selector: Movement] = [
        #selector(NSResponder.moveLeft(_:)): Movement(direction: .left, destination: .character, extending: false),
        #selector(NSResponder.moveRight(_:)): Movement(direction: .right, destination: .character, extending: false),
        #selector(NSResponder.moveUp(_:)): Movement(direction: .up, destination: .character, extending: false),
        #selector(NSResponder.moveDown(_:)): Movement(direction: .down, destination: .character, extending: false),
        #selector(NSResponder.moveBackward(_:)): Movement(direction: .backward, destination: .character, extending: false),
        #selector(NSResponder.moveForward(_:)): Movement(direction: .forward, destination: .character, extending: false),
        #selector(NSResponder.moveWordLeft(_:)): Movement(direction: .left, destination: .word, extending: false),
        #selector(NSResponder.moveWordRight(_:)): Movement(direction: .right, destination: .word, extending: false),
        #selector(NSResponder.moveToLeftEndOfLine(_:)): Movement(direction: .left, destination: .line, extending: false),
        #selector(NSResponder.moveToRightEndOfLine(_:)): Movement(direction: .right, destination: .line, extending: false),
        #selector(NSResponder.moveToBeginningOfLine(_:)): Movement(direction: .backward, destination: .line, extending: false),
        #selector(NSResponder.moveToEndOfLine(_:)): Movement(direction: .forward, destination: .line, extending: false),
        #selector(NSResponder.moveLeftAndModifySelection(_:)): Movement(direction: .left, destination: .character, extending: true),
        #selector(NSResponder.moveRightAndModifySelection(_:)): Movement(direction: .right, destination: .character, extending: true),
        #selector(NSResponder.moveUpAndModifySelection(_:)): Movement(direction: .up, destination: .character, extending: true),
        #selector(NSResponder.moveDownAndModifySelection(_:)): Movement(direction: .down, destination: .character, extending: true),
        #selector(NSResponder.moveWordLeftAndModifySelection(_:)): Movement(direction: .left, destination: .word, extending: true),
        #selector(NSResponder.moveWordRightAndModifySelection(_:)): Movement(direction: .right, destination: .word, extending: true),
        #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)):
            Movement(direction: .left, destination: .line, extending: true),
        #selector(NSResponder.moveToRightEndOfLineAndModifySelection(_:)):
            Movement(direction: .right, destination: .line, extending: true),
    ]

    static let deletions: [Selector: Deletion] = [
        #selector(NSResponder.deleteBackward(_:)): Deletion(direction: .backward, destination: .character, decomposes: false),
        #selector(NSResponder.deleteForward(_:)): Deletion(direction: .forward, destination: .character, decomposes: false),
        #selector(NSResponder.deleteBackwardByDecomposingPreviousCharacter(_:)):
            Deletion(direction: .backward, destination: .character, decomposes: true),
        #selector(NSResponder.deleteWordBackward(_:)): Deletion(direction: .backward, destination: .word, decomposes: false),
        #selector(NSResponder.deleteWordForward(_:)): Deletion(direction: .forward, destination: .word, decomposes: false),
        #selector(NSResponder.deleteToBeginningOfLine(_:)): Deletion(direction: .backward, destination: .line, decomposes: false),
        #selector(NSResponder.deleteToEndOfLine(_:)): Deletion(direction: .forward, destination: .line, decomposes: false),
    ]

    static let newlines: Set<Selector> = [
        #selector(NSResponder.insertNewline(_:)),
        #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
        #selector(NSResponder.insertLineBreak(_:)),
    ]

    /// What AppKit sends for a key with no binding.
    static let noop = NSSelectorFromString("noop:")

    static let tabs: Set<Selector> = [
        #selector(NSResponder.insertTab(_:)),
        #selector(NSResponder.insertTabIgnoringFieldEditor(_:)),
    ]
}
