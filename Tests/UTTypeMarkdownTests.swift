import Testing
import UniformTypeIdentifiers
@testable import MarkdownEditor

@Suite("UTType+Markdown")
struct UTTypeMarkdownTests {
    @Test("Markdown UTType has correct identifier")
    func markdownIdentifier() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
    }

    @Test("Markdown UTType conforms to plainText")
    func conformsToPlainText() {
        #expect(UTType.markdown.conforms(to: .plainText))
    }

    @Test("md extension resolves to markdown type")
    func mdExtension() {
        let type = UTType(filenameExtension: "md")
        #expect(type != nil)
    }
}
