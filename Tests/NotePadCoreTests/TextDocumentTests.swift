import Foundation
import Testing
@testable import NotePadCore

@Suite struct TextDocumentTests {
    @Test func untitledDocumentHasDefaultTitle() { #expect(TextDocument().title == "Untitled") }

    @Test func titleComesFromFileName() {
        #expect(TextDocument(fileURL: URL(fileURLWithPath: "/tmp/notes.txt")).title == "notes.txt")
    }

    @Test func recognizesMarkdownExtensions() {
        #expect(TextDocument(fileURL: URL(fileURLWithPath: "/a/README.MD")).isMarkdown)
        #expect(TextDocument(fileURL: URL(fileURLWithPath: "/a/b.markdown")).isMarkdown)
        #expect(!TextDocument(fileURL: URL(fileURLWithPath: "/a/b.txt")).isMarkdown)
        #expect(!TextDocument().isMarkdown)
    }

    @Test func formattedViewDefaultsToMarkdownFilesOnly() {
        let md = TextDocument(fileURL: URL(fileURLWithPath: "/a/b.md"))
        let txt = TextDocument(fileURL: URL(fileURLWithPath: "/a/b.txt"))
        #expect(md.usesFormattedView(formatAllText: false))
        #expect(!txt.usesFormattedView(formatAllText: false))
        #expect(txt.usesFormattedView(formatAllText: true))
        txt.formattedOverride = true
        #expect(txt.usesFormattedView(formatAllText: false))
    }

    @Test func wordWrapOverrideWinsOverDefault() {
        let doc = TextDocument()
        #expect(doc.usesWordWrap(default: true))
        doc.wordWrapOverride = false
        #expect(!doc.usesWordWrap(default: true))
    }

    @Test func zoomIsClamped() {
        let doc = TextDocument()
        doc.adjustZoom(by: 100)
        #expect(doc.zoom == 5)
        doc.adjustZoom(by: 0.0001)
        #expect(doc.zoom == 0.25)
    }

    @Test func snapshotRoundTripKeepsEverything() {
        let doc = TextDocument(
            text: "hello", fileURL: URL(fileURLWithPath: "/tmp/a.md"), encoding: .utf16LE, lineEnding: .crlf, isDirty: true
        )
        doc.selection = NSRange(location: 2, length: 3)
        doc.zoom = 1.5
        doc.wordWrapOverride = false
        doc.formattedOverride = true
        doc.previewVisible = true
        doc.scrollOffsetY = 120
        let restored = TextDocument(snapshot: doc.snapshot)
        #expect(restored.snapshot == doc.snapshot)
        #expect(restored.fileURL?.path == "/tmp/a.md")
        #expect(restored.selection == NSRange(location: 2, length: 3))
    }

    @Test func markSavedClearsDirtyAndSetsURL() {
        let doc = TextDocument(text: "x", isDirty: true)
        doc.markSaved(to: URL(fileURLWithPath: "/tmp/x.txt"), modificationDate: Date(timeIntervalSince1970: 5))
        #expect(!doc.isDirty)
        #expect(doc.title == "x.txt")
        #expect(doc.diskModificationDate == Date(timeIntervalSince1970: 5))
    }
}
