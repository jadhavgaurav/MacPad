import AppKit
import SwiftUI

/// Shows an EditorController's scroll view inside SwiftUI.
struct EditorHost: NSViewRepresentable {
    let controller: EditorController
    let settings: EditorSettings
    let zoom: Double
    let wrap: Bool
    let formatted: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        embed(controller.scrollView, in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if controller.scrollView.superview !== container { embed(controller.scrollView, in: container) }
        controller.apply(settings: settings, zoom: zoom, wrap: wrap, formatted: formatted)
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
