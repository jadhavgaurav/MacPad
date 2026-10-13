import AppKit
import MarkdownRendering
import MacPadCore
import SwiftUI
import WebKit

/// A find query to highlight in the rendered page. `current` is the editor's current match, which is
/// the same match only when the rendered text has as many matches as the source.
struct PreviewFind: Equatable {
    let query: String
    let matchCase: Bool
    let current: Int?
}

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    /// The source line the preview should show at its top.
    let scrollLine: Int
    let onScroll: (Int) -> Void
    let onHeading: (Int) -> Void
    let find: PreviewFind?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Scripts run only from PreviewScript, which is embedded in the page. Raw HTML in the Markdown is escaped.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: PreviewScript.handlerName)
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.setAccessibilityLabel("Markdown preview")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onHeading = onHeading
        context.coordinator.update(view, markdown: markdown, scrollLine: scrollLine, find: find)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: PreviewScript.handlerName)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onScroll: (Int) -> Void = { _ in }
        var onHeading: (Int) -> Void = { _ in }
        private var lastMarkdown: String?
        private var renderTask: Task<Void, Never>?
        private var line = 1
        private var find: PreviewFind?

        func update(_ view: WKWebView, markdown: String, scrollLine: Int, find: PreviewFind?) {
            line = scrollLine
            let findChanged = find != self.find
            self.find = find
            if markdown != lastMarkdown {
                lastMarkdown = markdown
                renderTask?.cancel()
                renderTask = Task { @MainActor [weak view] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let view else { return }
                    view.loadHTMLString(PreviewHTML.page(body: MarkdownHTML.render(markdown)), baseURL: nil)
                }
            } else {
                // A changed search scrolls to its current match instead of the editor's line.
                if findChanged { highlight(view) } else { scroll(view) }
            }
        }

        private func scroll(_ view: WKWebView) {
            view.evaluateJavaScript("window.notepadScrollToLine && window.notepadScrollToLine(\(line));", completionHandler: nil)
        }

        /// Marks the find matches on the page, or clears the marks when no search is active.
        private func highlight(_ view: WKWebView) {
            let arguments: [Any] = find.map { [$0.query, $0.matchCase, $0.current as Any? ?? NSNull()] }
                ?? ["", false, NSNull()]
            guard let data = try? JSONSerialization.data(withJSONObject: arguments),
                  let json = String(data: data, encoding: .utf8) else { return }
            view.evaluateJavaScript("window.notepadHighlight && window.notepadHighlight.apply(null, \(json));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            highlight(webView)
            if find == nil { scroll(webView) }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let value = body["line"] as? NSNumber else { return }
            switch body["type"] as? String {
            case "scroll": onScroll(value.intValue)
            case "heading": onHeading(value.intValue)
            default: break
            }
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}

enum PreviewHTML {
    static func page(body: String) -> String {
        MarkdownPage.document(body: body, script: PreviewScript.source)
    }
}
