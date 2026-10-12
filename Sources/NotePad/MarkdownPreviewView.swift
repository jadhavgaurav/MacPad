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
        MarkdownPage.document(body: body)
    }
}
