import AppKit

/// A thin scroll indicator that draws only the thumb. The default scroller draws a track box, which reads as broken
/// next to the glass bars.
class SlimScroller: NSScroller {
    private static let thumbInset: CGFloat = 3

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Intentionally empty: no track behind the thumb.
    }

    override func drawKnob() {
        let thumb = rect(for: .knob).insetBy(dx: Self.thumbInset, dy: Self.thumbInset)
        guard thumb.width > 0, thumb.height > 0 else { return }
        let radius = thumb.width / 2
        NSColor.labelColor.withAlphaComponent(0.32).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: radius, yRadius: radius).fill()
    }
}
