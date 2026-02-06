import Testing
@testable import MarkdownEditor

@Suite("MarkdownParser")
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
}
