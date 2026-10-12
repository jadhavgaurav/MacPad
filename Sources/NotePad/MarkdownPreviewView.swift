import AppKit
import MarkdownRendering
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let scrollFraction: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.setAccessibilityLabel("Markdown preview")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(view, markdown: markdown, scrollFraction: scrollFraction)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var lastMarkdown: String?
        private var renderTask: Task<Void, Never>?
        private var fraction = 0.0

        func update(_ view: WKWebView, markdown: String, scrollFraction: Double) {
            fraction = scrollFraction
            if markdown != lastMarkdown {
                lastMarkdown = markdown
                renderTask?.cancel()
                renderTask = Task { @MainActor [weak view] in
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, let view else { return }
                    view.loadHTMLString(PreviewHTML.page(body: MarkdownHTML.render(markdown)), baseURL: nil)
                }
            } else {
                scroll(view)
            }
        }

        private func scroll(_ view: WKWebView) {
            let script = "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(fraction));"
            view.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { scroll(webView) }

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
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.65 -apple-system, system-ui, sans-serif; margin: 0; padding: 64px 36px 72px;
               max-width: 680px; color: CanvasText; background: transparent; }
        h1 { font-size: 26px; margin: 0 0 12px; letter-spacing: -0.01em; }
        h2 { font-size: 19px; margin: 28px 0 8px; } h3 { font-size: 16px; margin: 22px 0 6px; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 12px; }
        a { color: LinkText; }
        code { font: 12.5px ui-monospace, "SF Mono", Menlo, monospace; background: rgba(127,127,127,.16);
               padding: 1px 5px; border-radius: 5px; }
        pre { background: rgba(127,127,127,.12); padding: 12px 14px; border-radius: 10px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid rgba(127,127,127,.4); padding-left: 14px; color: GrayText; margin-left: 0; }
        table { border-collapse: collapse; } th, td { border: 1px solid rgba(127,127,127,.3); padding: 6px 10px; }
        hr { border: 0; border-top: 1px solid rgba(127,127,127,.3); margin: 20px 0; }
        </style></head><body>\(body)</body></html>
        """
    }
}
