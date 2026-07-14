import Testing
@testable import MarkdownEditor

@Suite("MarkdownParser", .serialized)
struct MarkdownParserTests {
    let parser = MarkdownParser()

    @Test("Parse heading to HTML")
    func parseHeading() {
        let result = parser.parse("# Hello")
        #expect(result.contains("<h1>"))
        #expect(result.contains("Hello"))
    }

    @Test("Parse bold text")
    func parseBold() {
        let result = parser.parse("**bold**")
        #expect(result.contains("<strong>bold</strong>"))
    }

    @Test("Parse GFM table")
    func parseTable() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let result = parser.parse(md)
        #expect(result.contains("<table>"))
    }

    @Test("Parse GFM task list")
    func parseTaskList() {
        let md = "- [x] Done\n- [ ] Todo"
        let result = parser.parse(md)
        #expect(result.contains("checked"))
    }

    @Test("Parse strikethrough")
    func parseStrikethrough() {
        let md = "This is ~~deleted~~ text"
        let result = parser.parse(md)
        // cmark-gfm may render strikethrough as <del> or <s>
        let hasStrikethrough = result.contains("<del>") || result.contains("<s>")
        #expect(hasStrikethrough, "Expected strikethrough HTML but got: \(result)")
    }

    @Test("Parse fenced code block")
    func parseCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let result = parser.parse(md)
        #expect(result.contains("<code"))
    }

    @Test("Strip YAML front matter")
    func stripYAMLFrontMatter() {
        let md = "---\ntitle: Test\n---\n# Content"
        let result = parser.parse(md)
        #expect(!result.contains("title: Test"))
        #expect(result.contains("<h1>"))
    }

    @Test("Empty string returns empty")
    func parseEmpty() {
        let result = parser.parse("")
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Raw script tags are neutralized (tagfilter)")
    func scriptTagsFiltered() {
        let md = "hello\n\n<script>alert(1)</script>\n\nworld"
        let result = parser.parse(md)
        #expect(!result.contains("<script>"), "Expected <script> to be escaped but got: \(result)")
    }

    @Test("Extract front matter from CRLF document")
    func extractFrontMatterCRLF() {
        let md = "---\r\ntitle: Test\r\n---\r\n# Content"
        let result = parser.extractFrontMatter(md)
        #expect(result == "title: Test")
    }

    @Test("Extract front matter from LF document")
    func extractFrontMatterLF() {
        let md = "---\ntitle: Test\n---\n# Content"
        let result = parser.extractFrontMatter(md)
        #expect(result == "title: Test")
    }

    @Test("A ---- separator inside front matter is not the close delimiter")
    func frontMatterDashRuleNotClose() {
        let md = "---\ntitle: A\n----\nkey: B\n---\nbody"
        #expect(parser.extractFrontMatter(md) == "title: A\n----\nkey: B")
        #expect(parser.parse(md).contains("body"))
    }

    @Test("Strip YAML front matter from CRLF document")
    func stripFrontMatterCRLF() {
        let md = "---\r\ntitle: Test\r\n---\r\n# Content"
        let result = parser.parse(md)
        #expect(!result.contains("title: Test"))
        #expect(result.contains("<h1>"))
    }
}
