import Testing
@testable import MarkdownRendering

@Suite struct MarkdownHTMLTests {
    @Test func rendersHeadingAndParagraph() {
        let html = MarkdownHTML.render("# Title\n\nHello **world**.")
        #expect(html.contains("<h1 data-line=\"1\">Title</h1>"))
        #expect(html.contains("<p data-line=\"3\">Hello <strong>world</strong>.</p>"))
    }
    @Test func rendersLists() {
        let html = MarkdownHTML.render("- one\n- two\n\n1. a\n2. b")
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li data-line=\"1\">one</li>"))
        #expect(html.contains("<ol>"))
    }
    @Test func escapesRawHTML() {
        let html = MarkdownHTML.render("<script>alert(1)</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }
    @Test func dropsUnsafeLinkSchemes() {
        let html = MarkdownHTML.render("[x](javascript:alert(1)) [ok](https://example.com)")
        #expect(!html.contains("javascript:"))
        #expect(html.contains("<a href=\"https://example.com\">ok</a>"))
    }
    @Test func doesNotLoadRemoteImages() {
        let html = MarkdownHTML.render("![logo](https://example.com/a.png)")
        #expect(!html.contains("<img"))
        #expect(html.contains("logo"))
    }
    @Test func rendersCodeBlockEscaped() {
        let html = MarkdownHTML.render("```\na < b\n```")
        #expect(html.contains("<pre data-line=\"1\"><code>a &lt; b"))
    }
    @Test func rendersTable() {
        let html = MarkdownHTML.render("| a | b |\n|---|---|\n| 1 | 2 |")
        #expect(html.contains("<th>a</th>"))
        #expect(html.contains("<td>2</td>"))
    }
}

@Suite struct MarkdownPageTests {
    @Test func pageHasDoctypeEscapedTitleAndBody() {
        let page = MarkdownPage.document(body: "<h1>Hi</h1>", title: "A & B")
        #expect(page.hasPrefix("<!doctype html>"))
        #expect(page.contains("<title>A &amp; B</title>"))
        #expect(page.contains("<h1>Hi</h1>"))
    }
    @Test func pageWithoutTitleHasNoTitleTag() {
        #expect(!MarkdownPage.document(body: "x").contains("<title>"))
    }
}
