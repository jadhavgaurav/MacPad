import AppKit

/// Gutter that numbers the logical lines of an NSTextView. Only lines that start in the visible area are drawn.
final class LineNumberRuler: NSRulerView {
    private static let minimumThickness: CGFloat = 36
    private static let padding: CGFloat = 10

    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var lineStartsSource = ""

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.minimumThickness
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("LineNumberRuler is created in code only") }

    override var isFlipped: Bool { true }

    /// Call after the text changes so the gutter width and cached line starts stay correct.
    func textDidChange() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Opaque, so text scrolled horizontally never shows through the number column.
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        guard let textView, let layoutManager = textView.textLayoutManager,
              let contentStorage = layoutManager.textContentManager as? NSTextContentStorage else { return }

        refreshLineStarts(textView.string)
        let digits = max(2, String(lineStarts.count).count)
        let width = max(Self.minimumThickness, CGFloat(digits) * 8 + Self.padding * 2)
        if ruleThickness != width { ruleThickness = width }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let visible = textView.visibleRect
        guard let first = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY)) else { return }
        let documentStart = contentStorage.documentRange.location

        var lastFrame: CGRect?
        var reachedEnd = false
        layoutManager.enumerateTextLayoutFragments(from: first.rangeInElement.location, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > visible.maxY { return false }
            lastFrame = frame
            let fragmentEnd = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
            reachedEnd = fragmentEnd == contentStorage.offset(from: documentStart, to: layoutManager.documentRange.endLocation)
            let offset = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
            if let line = lineNumber(startingAtUTF16Offset: offset) {
                drawLabel(line, at: frame, attributes: attributes, in: textView)
            }
            return true
        }

        // A trailing newline starts a final empty line that has no layout fragment of its own.
        if reachedEnd, let lastFrame, textView.string.hasSuffix("\n") {
            let emptyLine = lineStarts.count
            let frame = CGRect(x: lastFrame.minX, y: lastFrame.maxY, width: lastFrame.width, height: lastFrame.height)
            if frame.minY <= visible.maxY { drawLabel(emptyLine, at: frame, attributes: attributes, in: textView) }
        }
    }

    private func drawLabel(_ line: Int, at frame: CGRect, attributes: [NSAttributedString.Key: Any], in textView: NSTextView) {
        // Fragment frames are in text container coordinates, which sit inside the text view's inset.
        let inContainer = NSPoint(x: 0, y: frame.minY + textView.textContainerOrigin.y)
        let origin = convert(inContainer, from: textView)
        let label = "\(line)" as NSString
        let size = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: bounds.width - Self.padding - size.width, y: origin.y + (frame.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    private func refreshLineStarts(_ text: String) {
        guard text != lineStartsSource else { return }
        lineStartsSource = text
        var starts = [0]
        let ns = text as NSString
        var index = 0
        while index < ns.length {
            let found = ns.range(of: "\n", options: .literal, range: NSRange(location: index, length: ns.length - index))
            if found.location == NSNotFound { break }
            starts.append(found.location + 1)
            index = found.location + 1
        }
        lineStarts = starts
    }

    /// 1-based line number when a fragment begins a logical line, otherwise nil (wrapped continuation).
    private func lineNumber(startingAtUTF16Offset offset: Int) -> Int? {
        var low = 0
        var high = lineStarts.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] == offset { return mid + 1 }
            if lineStarts[mid] < offset { low = mid + 1 } else { high = mid - 1 }
        }
        return nil
    }
}
