import AppKit
import SwiftUI

extension View {
    /// Shows the pointing-hand cursor over a control that acts on click. The editor keeps its I-beam.
    func pointingHandCursor() -> some View { modifier(PointingHandCursor()) }
}

private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            content.onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}
