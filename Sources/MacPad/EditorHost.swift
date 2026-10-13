import AppKit
import SwiftUI

/// Shows an EditorController's scroll view inside SwiftUI.
struct EditorHost: NSViewRepresentable {
    let controller: EditorController
    let settings: EditorSettings
    let zoom: Double
    let wrap: Bool
    let formatted: Bool
    let showLineNumbers: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        embed(controller.scrollView, in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // Embed only when nothing holds the view. When a tab moves to another window, that window's container takes
        // the view. This old container must not take it back, or the moved tab would lose its editor.
        if controller.scrollView.superview == nil { embed(controller.scrollView, in: container) }
        controller.apply(settings: settings, zoom: zoom, wrap: wrap, formatted: formatted, showLineNumbers: showLineNumbers)
    }

    private func embed(_ scrollView: NSScrollView, in container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        DispatchQueue.main.async { controller.focus() }
    }
}
