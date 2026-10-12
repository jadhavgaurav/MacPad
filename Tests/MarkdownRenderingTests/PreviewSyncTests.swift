import Testing
@testable import MarkdownRendering

@Suite struct PreviewSyncTests {
    @Test func blocksCarryTheirSourceLine() {
        let html = MarkdownHTML.render("# Title\n\nFirst paragraph.\n\n## Second\n\n- item\n")
        #expect(html.contains("<h1 data-line=\"1\">"))
        #expect(html.contains("<p data-line=\"3\">"))
        #expect(html.contains("<h2 data-line=\"5\">"))
        #expect(html.contains("<li data-line=\"7\">"))
    }

    @Test func codeBlocksCarryTheirSourceLine() {
        let html = MarkdownHTML.render("text\n\n```\ncode\n```\n")
        #expect(html.contains("<pre data-line=\"3\">"))
    }

    @Test func previewPageIncludesScriptAndAllowsIt() {
        let page = MarkdownPage.document(body: "<p>x</p>", script: "window.ok = true;")
        #expect(page.contains("<script>window.ok = true;</script>"))
        #expect(page.contains("script-src 'unsafe-inline'"))
    }

    @Test func exportPageHasNoScriptAndNoScriptPolicy() {
        let page = MarkdownPage.document(body: "<p>x</p>")
        #expect(!page.contains("<script"))
        #expect(!page.contains("script-src"))
    }
}
