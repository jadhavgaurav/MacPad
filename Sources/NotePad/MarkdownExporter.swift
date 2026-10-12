import AppKit
import MarkdownRendering
import WebKit

/// Writes the active Markdown document as an HTML file or a PDF.
@MainActor
enum MarkdownExporter {
    static func exportHTML(markdown: String, title: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = suggestedName + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = MarkdownPage.document(body: MarkdownHTML.render(markdown), title: title)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Dialogs.showError(error)
        }
    }

    /// Renders the page offscreen and saves it as a PDF. The web view is kept alive until the PDF is written.
    static func exportPDF(markdown: String, title: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = suggestedName + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = MarkdownPage.document(body: MarkdownHTML.render(markdown), title: title)
        let renderer = PDFRenderer(html: html, destination: url)
        pending.append(renderer)
        renderer.start { [weak renderer] in
            pending.removeAll { $0 === renderer }
        }
    }

    private static var pending: [PDFRenderer] = []
}

@MainActor
private final class PDFRenderer: NSObject, WKNavigationDelegate {
    private let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 816, height: 1056))
    private let html: String
    private let destination: URL
    private var finished: (() -> Void)?

    init(html: String, destination: URL) {
        self.html = html
        self.destination = destination
        super.init()
        webView.navigationDelegate = self
    }

    func start(finished: @escaping () -> Void) {
        self.finished = finished
        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.createPDF(configuration: WKPDFConfiguration()) { [destination] result in
            Task { @MainActor in
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: destination, options: .atomic)
                    } catch {
                        Dialogs.showError(error)
                    }
                case .failure(let error):
                    Dialogs.showError(error)
                }
                self.finished?()
            }
        }
    }
}
