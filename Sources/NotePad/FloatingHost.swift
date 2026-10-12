import AppKit
import SwiftUI

/// Hosts SwiftUI content in its own AppKit view, so it sits above the editor's text view.
/// Without this, the text view's I-beam cursor rect covers the floating bar and the pointing-hand cursors inside it never apply.
struct FloatingHost<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        NSHostingView(rootView: content)
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content
    }
}
