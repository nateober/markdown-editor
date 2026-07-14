import Foundation
import libcmark_gfm

final class MarkdownParser {

    init() {
        cmark_gfm_core_extensions_ensure_registered()
    }

    func parse(_ markdown: String) -> String {
        let stripped = stripFrontMatter(markdown)
        return renderToHTML(stripped)
    }

    // NOTE: "\r\n" is a single Character in Swift, so both "---\n" and
    // "---\r\n" are 4 Characters — dropFirst(4) is correct for either.
    // The closing delimiter is located with one regex shared by extract and
    // strip so the two can never disagree about where front matter ends;
    // it requires a full "---" line (a "----" separator inside the YAML is
    // not a close), and handles CRLF, which a plain range(of: "\n---")
    // cannot (it never matches inside a "\r\n" grapheme).

    func extractFrontMatter(_ markdown: String) -> String? {
        splitFrontMatter(markdown)?.frontMatter
    }

    private func stripFrontMatter(_ markdown: String) -> String {
        splitFrontMatter(markdown)?.body ?? markdown
    }

    /// Matches the closing "---" delimiter line: a newline (LF or CRLF),
    /// exactly "---", then a newline or end of input. Requiring the full
    /// line means a "----" separator inside the YAML is not mistaken for
    /// the close. (NSRegularExpression, not range(of:.regularExpression) —
    /// the latter fails to match \r?\n patterns across CRLF graphemes.)
    private static let frontMatterClose = try! NSRegularExpression(pattern: #"\r?\n---(\r?\n|\z)"#)

    /// Splits a document with YAML front matter into (frontMatter, body).
    /// Returns nil when there is no opener or no closing delimiter — shared
    /// by extract and strip so the two can never disagree.
    private func splitFrontMatter(_ markdown: String) -> (frontMatter: String, body: String)? {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return nil }
        // "\r\n" is a single Character in Swift, so both openers are 4 long.
        let content = String(markdown.dropFirst(4))
        let ns = content as NSString
        guard let match = Self.frontMatterClose.firstMatch(
            in: content, range: NSRange(location: 0, length: ns.length)
        ) else { return nil }
        return (
            frontMatter: ns.substring(to: match.range.location),
            body: ns.substring(from: NSMaxRange(match.range))
        )
    }

    private func renderToHTML(_ markdown: String) -> String {
        // Ensure extensions are registered before each parse call
        cmark_gfm_core_extensions_ensure_registered()

        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        // tagfilter is essential alongside CMARK_OPT_UNSAFE: it neutralizes
        // dangerous raw tags (<script>, <iframe>, ...) that would otherwise
        // pass through verbatim into the preview and exported HTML/PDF.
        let extensionNames = ["table", "strikethrough", "tasklist", "autolink", "tagfilter"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        markdown.withCString { ptr in
            cmark_parser_feed(parser, ptr, strlen(ptr))
        }

        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        guard let html = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }

        return String(cString: html)
    }
}
