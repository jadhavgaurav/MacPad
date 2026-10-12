import Foundation

/// A complete HTML page for rendered Markdown. The preview and exported files use the same stylesheet.
public enum MarkdownPage {
    public static func document(body: String, title: String = "") -> String {
        let heading = title.isEmpty ? "" : "<title>\(MarkdownHTML.escape(title))</title>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(heading)
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
