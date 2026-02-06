import Testing
import UniformTypeIdentifiers
@testable import MarkdownEditor

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {
    @Test("New document has empty text")
    func newDocumentIsEmpty() {
        let doc = MarkdownDocument()
        #expect(doc.text == "")
    }

    @Test("Document reads from file data")
    func readFromData() throws {
        let markdown = "# Hello\n\nThis is a test."
        let data = Data(markdown.utf8)
        let doc = try MarkdownDocument(data: data)
        #expect(doc.text == markdown)
    }

    @Test("Document writes to data")
    func writeToData() throws {
        let doc = MarkdownDocument()
        doc.text = "# Test\n\nSome content."
        let data = try doc.dataForSaving()
        let result = String(data: data, encoding: .utf8)
        #expect(result == "# Test\n\nSome content.")
    }

    @Test("Document readable content types includes markdown")
    func readableContentTypes() {
        #expect(MarkdownDocument.readableContentTypes.contains(.markdown))
    }
}
