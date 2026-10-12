import Foundation

extension AppState {
    /// Exports the active Markdown tab. Plain text is exported as Markdown, which renders as plain paragraphs.
    func exportActive(asPDF: Bool) {
        guard let doc = activeDocument else { return }
        let name = doc.fileURL?.deletingPathExtension().lastPathComponent ?? doc.title
        if asPDF {
            MarkdownExporter.exportPDF(markdown: doc.text, title: name, suggestedName: name)
        } else {
            MarkdownExporter.exportHTML(markdown: doc.text, title: name, suggestedName: name)
        }
    }
}
