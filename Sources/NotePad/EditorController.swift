import AppKit
import MarkdownRendering
import NotePadCore

/// A text view that pastes plain text only, so formatting from other apps never leaks into a .txt file.
final class PlainTextView: NSTextView {
    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }
}

/// Owns one tab's NSTextView. Keeping one view per tab preserves undo history, selection and scroll when switching.
@MainActor
final class EditorController: NSObject, NSTextViewDelegate {
    let document: TextDocument
    let scrollView = NSScrollView()
    let textView = PlainTextView(usingTextLayoutManager: true)

    var onEdit: ((TextDocument) -> Void)?
    var onSelectionChange: ((TextDocument) -> Void)?
    var onScroll: ((TextDocument, Double) -> Void)?

    private var settings = EditorSettings()
    private var zoom = 1.0
    private var wrap = true
    private var formatted = false
    private var styleTask: Task<Void, Never>?
    private var isApplyingProgrammaticChange = false
    private var hasApplied = false

    private static let contentInset = NSSize(width: 24, height: 60)

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
            self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: self.document.scrollOffsetY))
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    // MARK: Setup

    private func configureViews() {
        textView.delegate = self
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
        textView.textContainerInset = Self.contentInset
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.setAccessibilityLabel("Editor")

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
    }

    // MARK: Appearance

    func apply(settings: EditorSettings, zoom: Double, wrap: Bool, formatted: Bool) {
        let isFirstApply = !hasApplied
        hasApplied = true
        let fontChanged = isFirstApply || settings != self.settings || zoom != self.zoom
        let wrapChanged = isFirstApply || wrap != self.wrap
        let formattedChanged = isFirstApply || formatted != self.formatted
        self.settings = settings
        self.zoom = zoom
        self.wrap = wrap
        self.formatted = formatted
        if wrapChanged || fontChanged { applyWrap() }
        if fontChanged || formattedChanged { restyle() }
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

    var scrollFraction: Double {
        let documentHeight = textView.frame.height
        let visible = scrollView.contentView.bounds.height
        let travel = max(documentHeight - visible, 1)
        return min(max(scrollView.contentView.bounds.origin.y / travel, 0), 1)
    }

    // MARK: NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
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
        document.scrollOffsetY = scrollView.contentView.bounds.origin.y
        onScroll?(document, scrollFraction)
    }
}
