import SwiftUI

/// Liquid Glass on macOS 26 and later, a system material with a hairline edge before that.
extension View {
    func glassCapsule() -> some View { modifier(GlassModifier(shape: Capsule())) }

    func glassRounded(_ radius: CGFloat = 14) -> some View {
        modifier(GlassModifier(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }
}

private struct GlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

/// Lets neighboring glass shapes blend and morph on macOS 26. A plain container before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
