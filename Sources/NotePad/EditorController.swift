import AppKit
import MarkdownRendering
import NotePadCore

/// A text view that pastes plain text only, so formatting from other apps never leaks into a .txt file.
final class PlainTextView: NSTextView {
    /// Receives the zoom factor for a Command + scroll gesture.
    var onCommandScroll: ((CGFloat) -> Void)?

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    /// The offset where an Option-drag column selection started. Nil when no column drag is in progress.
    private var columnAnchor: Int?

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
        setSelectedRange(NSRange(location: NSMaxRange(last), length: 0))
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

/// Owns one tab's NSTextView. Keeping one view per tab preserves undo history, selection and scroll when switching.
@MainActor
final class EditorController: NSObject, NSTextViewDelegate {
    let document: TextDocument
    let scrollView = NSScrollView()
    let textView = PlainTextView(usingTextLayoutManager: true)

    var onEdit: ((TextDocument) -> Void)?
    var onSelectionChange: ((TextDocument) -> Void)?
    var onScroll: ((TextDocument, Int) -> Void)?
    /// Called with a zoom factor when the user zooms with Command + scroll.
    var onZoom: ((CGFloat) -> Void)?

    private var settings = EditorSettings()
    private var zoom = 1.0
    private var wrap = true
    private var formatted = false
    private var styleTask: Task<Void, Never>?
    private var isApplyingProgrammaticChange = false
    private var hasApplied = false

    /// Space for the floating glass bars. The text scrolls under them but starts and ends clear of them.
    private var ruler: LineNumberRuler?
    private var showsLineNumbers = false

    private static let barInsets = NSEdgeInsets(top: 84, left: 0, bottom: 64, right: 0)
    private static let textInset = NSSize(width: 28, height: 12)

    init(document: TextDocument) {
        self.document = document
        super.init()
        configureViews()
        textView.string = document.text
        let length = (document.text as NSString).length
        let location = min(document.selection.location, length)
        textView.setSelectedRange(NSRange(location: location, length: min(document.selection.length, length - location)))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Lay out first so the line-number gutter has its width, then restore only the vertical position.
            // The horizontal origin is whatever layout gave the clip view, so text starts at its normal inset.
            self.scrollView.layoutSubtreeIfNeeded()
            let horizontal = self.scrollView.contentView.bounds.origin.x
            let origin = NSPoint(x: horizontal, y: self.document.scrollOffsetY - Self.barInsets.top)
            self.scrollView.contentView.scroll(to: origin)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    // MARK: Setup

    private func configureViews() {
        textView.delegate = self
        textView.onCommandScroll = { [weak self] factor in self?.onZoom?(factor) }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = false
        textView.usesFontPanel = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = Self.textInset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.setAccessibilityLabel("Editor")

        scrollView.documentView = textView
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller = SlimScroller()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = Self.barInsets
        // Keep the scroller inside the window margin, clear of the window edge and the trailing glass capsules.
        scrollView.scrollerInsets = NSEdgeInsets(top: Self.barInsets.top, left: 0, bottom: Self.barInsets.bottom, right: 8)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
    }

    // MARK: Appearance

    func apply(settings: EditorSettings, zoom: Double, wrap: Bool, formatted: Bool, showLineNumbers: Bool) {
        textView.isEditable = !document.isReadOnly
        if showLineNumbers != showsLineNumbers { setLineNumbers(showLineNumbers) }
        let isFirstApply = !hasApplied
        hasApplied = true
        let fontChanged = isFirstApply || settings != self.settings || zoom != self.zoom
        let wrapChanged = isFirstApply || wrap != self.wrap
        let formattedChanged = isFirstApply || formatted != self.formatted
        self.settings = settings
        self.zoom = zoom
        self.wrap = wrap
        self.formatted = formatted
        // Text typed from now on inherits the editor's font and line height, so new lines line up with the gutter.
        textView.typingAttributes = baseAttributes
        if wrapChanged || fontChanged { applyWrap() }
        if fontChanged || formattedChanged { restyle() }
        // Font size, zoom and wrap change the line metrics the gutter reads, so redraw it once layout has settled.
        if fontChanged || wrapChanged || formattedChanged {
            DispatchQueue.main.async { [weak self] in self?.ruler?.textDidChange() }
        }
    }

    private func setLineNumbers(_ visible: Bool) {
        showsLineNumbers = visible
        if visible {
            let ruler = self.ruler ?? LineNumberRuler(scrollView: scrollView, textView: textView)
            self.ruler = ruler
            scrollView.verticalRulerView = ruler
        }
        scrollView.hasVerticalRuler = visible
        scrollView.rulersVisible = visible
        ruler?.needsDisplay = true
    }

    private func applyWrap() {
        guard let container = textView.textContainer else { return }
        textView.isHorizontallyResizable = !wrap
        container.widthTracksTextView = wrap
        container.containerSize = NSSize(
            width: wrap ? max(scrollView.contentSize.width, 1) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.hasHorizontalScroller = !wrap
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.3
        return [.font: settings.font(zoom: zoom), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private func restyle() {
        guard let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        textView.typingAttributes = baseAttributes
        isApplyingProgrammaticChange = true
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        if formatted {
            let spans = MarkdownStyler.spans(for: textView.string)
            for span in spans where span.kind != .marker { style(span, in: storage) }
            for span in spans where span.kind == .marker { style(span, in: storage) }
        }
        storage.endEditing()
        isApplyingProgrammaticChange = false
    }

    private func scheduleRestyle() {
        guard formatted else { return }
        styleTask?.cancel()
        styleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.restyle()
        }
    }

    private func style(_ span: StyleSpan, in storage: NSTextStorage) {
        let range = NSIntersectionRange(span.range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        let base = settings.font(zoom: zoom)
        let current = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? base
        let manager = NSFontManager.shared
        switch span.kind {
        case .heading(let level):
            let scales: [CGFloat] = [1.8, 1.5, 1.3, 1.15, 1.05, 1.0]
            let scaled = NSFont(descriptor: base.fontDescriptor, size: base.pointSize * scales[min(max(level, 1), 6) - 1]) ?? base
            storage.addAttribute(.font, value: manager.convert(scaled, toHaveTrait: .boldFontMask), range: range)
        case .strong:
            storage.addAttribute(.font, value: manager.convert(current, toHaveTrait: .boldFontMask), range: range)
        case .emphasis:
            let italic = manager.convert(current, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: range)
            if italic == current { storage.addAttribute(.obliqueness, value: 0.2, range: range) }
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode, .codeBlock:
            storage.addAttribute(.backgroundColor, value: NSColor.labelColor.withAlphaComponent(0.07), range: range)
        case .link(let destination):
            storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            if let url = URL(string: destination) { storage.addAttribute(.link, value: url, range: range) }
        case .listMarker:
            storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
        case .quote:
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
        case .marker:
            storage.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor, .underlineStyle: 0], range: range)
        }
    }

    // MARK: Commands

    func focus() { textView.window?.makeFirstResponder(textView) }

    func addNextOccurrence() {
        textView.addNextOccurrence()
        focus()
    }

    func addCaret(_ direction: MultiCursor.VerticalDirection) {
        textView.addCaret(direction)
        focus()
    }

    func apply(_ command: MarkdownCommand) {
        let result = MarkdownFormatter.apply(command, to: textView.string, selection: textView.selectedRange())
        replaceWholeText(result.text, selecting: result.selection)
        focus()
    }

    func replaceWholeText(_ newText: String, selecting selection: NSRange? = nil) {
        let edit = MinimalEdit(from: textView.string, to: newText)
        if !edit.isNoOp, textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        }
        if let selection { textView.setSelectedRange(selection) }
    }

    var selectedText: String {
        (textView.string as NSString).substring(with: textView.selectedRange())
    }

    /// Replaces the selection with `text` as one undoable edit, then puts the caret at `caretOffset` within it.
    func insertText(_ text: String, caretOffset: Int?) {
        let range = textView.selectedRange()
        textView.insertText(text, replacementRange: range)
        let caret = range.location + (caretOffset ?? (text as NSString).length)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        focus()
    }

    func replaceCharacters(in range: NSRange, with string: String) {
        guard textView.shouldChangeText(in: range, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }

    /// Replaces the buffer after a reload from disk. Clears undo history because the old edits no longer apply.
    func reset(text: String) {
        textView.undoManager?.removeAllActions()
        textView.string = text
        document.text = text
        restyle()
    }

    func select(_ range: NSRange, scrollToVisible: Bool = true) {
        textView.setSelectedRange(range)
        if scrollToVisible { textView.scrollRangeToVisible(range) }
    }

    func setFindHighlights(_ matches: [NSRange], current: Int?) {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager as? NSTextContentStorage else { return }
        layout.removeRenderingAttribute(.backgroundColor, for: layout.documentRange)
        for (index, range) in matches.enumerated() {
            guard let start = content.location(content.documentRange.location, offsetBy: range.location),
                  let end = content.location(start, offsetBy: range.length),
                  let textRange = NSTextRange(location: start, end: end) else { continue }
            let color: NSColor = index == current
                ? NSColor.systemOrange.withAlphaComponent(0.55) : NSColor.systemYellow.withAlphaComponent(0.4)
            layout.addRenderingAttribute(.backgroundColor, value: color, for: textRange)
        }
    }

    /// The 1-based line at the top of the visible text, below the toolbar strip.
    var topVisibleLine: Int {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager as? NSTextContentStorage,
              let viewport = layout.textViewportLayoutController.viewportRange else { return 1 }
        let index = content.offset(from: content.documentRange.location, to: viewport.location)
        return LineLocator.position(at: index, in: textView.string).line
    }

    /// Scrolls so that `line` sits at the top of the visible text. The caret and selection do not move.
    func scrollToLine(_ line: Int) {
        guard let range = LineLocator.range(ofLine: line, in: textView.string),
              let layout = textView.textLayoutManager,
              let content = layout.textContentManager as? NSTextContentStorage,
              let location = content.location(content.documentRange.location, offsetBy: range.location),
              let fragment = layout.textLayoutFragment(for: location) else { return }
        let clip = scrollView.contentView
        let y = textView.textContainerOrigin.y + fragment.layoutFragmentFrame.minY - Self.barInsets.top
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        // The new line's layout is not ready until the next run-loop turn, so redraw the gutter then.
        DispatchQueue.main.async { [weak self] in self?.ruler?.textDidChange() }
        guard !isApplyingProgrammaticChange else { return }
        document.text = textView.string
        document.isDirty = true
        document.selection = textView.selectedRange()
        scheduleRestyle()
        onEdit?(document)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isApplyingProgrammaticChange else { return }
        document.selection = textView.selectedRange()
        onSelectionChange?(document)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard NSEvent.modifierFlags.contains(.command) else { return true }
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        if let url, ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return true
    }

    @objc private func boundsChanged() {
        document.scrollOffsetY = scrollView.contentView.bounds.origin.y + Self.barInsets.top
        onScroll?(document, topVisibleLine)
    }
}
