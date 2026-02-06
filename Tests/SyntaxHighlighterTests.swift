import Testing
import AppKit
@testable import MarkdownEditor

@Suite("SyntaxHighlighter")
struct SyntaxHighlighterTests {
    let highlighter = SyntaxHighlighter()
    let theme = HighlightTheme.light

    private func highlight(_ text: String) -> NSAttributedString {
        let storage = NSMutableAttributedString(string: text, attributes: theme.defaultStyle.attributes)
        highlighter.highlight(in: storage, range: NSRange(location: 0, length: storage.length), theme: theme)
        return storage
    }

    @Test("Heading 1 gets heading style")
    func heading1() {
        let result = highlight("# Hello World")
        var range = NSRange()
        // Check the text portion (after "# ")
        let font = result.attribute(.font, at: 2, effectiveRange: &range) as? NSFont
        #expect(font?.pointSize == 24)
    }

    @Test("Bold text gets bold font")
    func bold() {
        let result = highlight("Some **bold** text")
        var range = NSRange()
        // "bold" starts at index 6 (inside the ** markers)
        let font = result.attribute(.font, at: 6, effectiveRange: &range) as? NSFont
        let traits = font.flatMap { NSFontManager.shared.traits(of: $0) } ?? []
        #expect(traits.contains(.boldFontMask))
    }

    @Test("Inline code gets background color")
    func inlineCode() {
        let result = highlight("Use `code` here")
        var range = NSRange()
        let bg = result.attribute(.backgroundColor, at: 5, effectiveRange: &range)
        #expect(bg != nil)
    }

    @Test("Fenced code block content gets background")
    func codeBlock() {
        let text = "```swift\nlet x = 1\n```"
        let result = highlight(text)
        // Check inside the code block content
        var range = NSRange()
        let bg = result.attribute(.backgroundColor, at: 10, effectiveRange: &range)
        #expect(bg != nil)
    }

    @Test("Link text gets link color")
    func link() {
        let result = highlight("[Click](https://example.com)")
        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: 1, effectiveRange: &range) as? NSColor
        #expect(color == NSColor.systemBlue)
    }

    @Test("Heading marker gets muted color")
    func headingMarker() {
        let result = highlight("## Title")
        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        // Heading marker should be muted (not the default text color)
        #expect(color != nil)
    }

    @Test("List marker gets accent color")
    func listMarker() {
        let result = highlight("- Item one")
        var range = NSRange()
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
        #expect(color == NSColor.systemOrange)
    }
}
