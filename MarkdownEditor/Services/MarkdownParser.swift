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

    func extractFrontMatter(_ markdown: String) -> String? {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return nil }
        let content = markdown.dropFirst(4)
        guard let endRange = content.range(of: "\n---\n") ??
              content.range(of: "\n---\r\n") ??
              content.range(of: "\n---") else { return nil }
        return String(content[content.startIndex..<endRange.lowerBound])
    }

    private func stripFrontMatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return markdown }
        let content = markdown.dropFirst(4)
        if let endRange = content.range(of: "\n---\n") {
            return String(content[endRange.upperBound...])
        } else if let endRange = content.range(of: "\n---\r\n") {
            return String(content[endRange.upperBound...])
        } else if content.hasSuffix("\n---") {
            return ""
        }
        return markdown
    }

    private func renderToHTML(_ markdown: String) -> String {
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        let extensionNames = ["table", "strikethrough", "tasklist", "autolink"]
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
