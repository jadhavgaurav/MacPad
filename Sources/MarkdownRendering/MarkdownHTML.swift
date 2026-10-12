import Foundation
import Markdown

public enum MarkdownHTML {
    public static func render(_ source: String) -> String {
        var visitor = HTMLVisitor()
        return visitor.visit(Document(parsing: source))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func isSafeLink(_ destination: String) -> Bool {
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: Markup) -> String { renderChildren(of: markup) }

    mutating func renderChildren(of markup: Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        "<h\(heading.level)>\(renderChildren(of: heading))</h\(heading.level)>\n"
    }
    mutating func visitParagraph(_ paragraph: Paragraph) -> String { "<p>\(renderChildren(of: paragraph))</p>\n" }
    mutating func visitText(_ text: Text) -> String { MarkdownHTML.escape(text.string) }
    mutating func visitEmphasis(_ emphasis: Emphasis) -> String { "<em>\(renderChildren(of: emphasis))</em>" }
    mutating func visitStrong(_ strong: Strong) -> String { "<strong>\(renderChildren(of: strong))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(renderChildren(of: s))</del>" }
    mutating func visitInlineCode(_ code: InlineCode) -> String { "<code>\(MarkdownHTML.escape(code.code))</code>" }
    mutating func visitCodeBlock(_ block: CodeBlock) -> String {
        "<pre><code>\(MarkdownHTML.escape(block.code))</code></pre>\n"
    }
    mutating func visitBlockQuote(_ quote: BlockQuote) -> String { "<blockquote>\(renderChildren(of: quote))</blockquote>\n" }
    mutating func visitThematicBreak(_ rule: ThematicBreak) -> String { "<hr>\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }
    mutating func visitUnorderedList(_ list: UnorderedList) -> String { "<ul>\n\(renderChildren(of: list))</ul>\n" }
    mutating func visitOrderedList(_ list: OrderedList) -> String { "<ol>\n\(renderChildren(of: list))</ol>\n" }
    mutating func visitListItem(_ item: ListItem) -> String {
        var box = ""
        if let checkbox = item.checkbox {
            box = "<input type=\"checkbox\" disabled\(checkbox == .checked ? " checked" : "")> "
        }
        var body = ""
        for child in item.children {
            if let paragraph = child as? Paragraph { body += renderChildren(of: paragraph) } else { body += visit(child) }
        }
        return "<li>\(box)\(body)</li>\n"
    }
    mutating func visitLink(_ link: Link) -> String {
        let inner = renderChildren(of: link)
        guard let destination = link.destination, MarkdownHTML.isSafeLink(destination) else { return inner }
        return "<a href=\"\(MarkdownHTML.escape(destination))\">\(inner)</a>"
    }
    mutating func visitImage(_ image: Image) -> String { MarkdownHTML.escape(image.plainText) }
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { "<pre>\(MarkdownHTML.escape(html.rawHTML))</pre>\n" }
    mutating func visitInlineHTML(_ html: InlineHTML) -> String { MarkdownHTML.escape(html.rawHTML) }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        var out = "<table>\n<thead><tr>"
        for cell in table.head.cells { out += "<th>\(renderChildren(of: cell))</th>" }
        out += "</tr></thead>\n<tbody>\n"
        for row in table.body.rows {
            out += "<tr>"
            for cell in row.cells { out += "<td>\(renderChildren(of: cell))</td>" }
            out += "</tr>\n"
        }
        return out + "</tbody>\n</table>\n"
    }
}
