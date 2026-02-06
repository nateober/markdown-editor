import Testing
@testable import MarkdownEditor

@Suite("String+Markdown")
struct StringMarkdownTests {
    @Test("Word count for simple text")
    func wordCount() {
        #expect("Hello world".wordCount == 2)
    }

    @Test("Word count for empty string")
    func wordCountEmpty() {
        #expect("".wordCount == 0)
    }

    @Test("Word count ignores extra whitespace")
    func wordCountWhitespace() {
        #expect("  hello   world  ".wordCount == 2)
    }

    @Test("Character count")
    func characterCount() {
        #expect("Hello".characterCount == 5)
    }

    @Test("Reading time for short text")
    func readingTimeShort() {
        let text = Array(repeating: "word", count: 200).joined(separator: " ")
        #expect(text.readingTimeMinutes == 1)
    }

    @Test("Reading time for longer text")
    func readingTimeLonger() {
        let text = Array(repeating: "word", count: 600).joined(separator: " ")
        #expect(text.readingTimeMinutes == 3)
    }

    @Test("Reading time for empty text is zero")
    func readingTimeEmpty() {
        #expect("".readingTimeMinutes == 0)
    }
}
