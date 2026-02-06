import Testing
@testable import MarkdownEditor

@Suite("PreviewHTMLGenerator")
struct PreviewHTMLGeneratorTests {
    let generator = PreviewHTMLGenerator()

    @Test("Generates HTML containing parsed content")
    func generatesHTML() {
        let html = generator.generateBody(from: "# Hello")
        #expect(html.contains("<h1>"))
    }

    @Test("Math content passes through")
    func mathPassthrough() {
        let html = generator.generateBody(from: "Inline $x^2$ math")
        #expect(html.contains("x^2"))
    }
}
