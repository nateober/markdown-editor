import SwiftUI
import UniformTypeIdentifiers

final class MarkdownDocument: ReferenceFileDocument {
    @Published var text: String

    static var readableContentTypes: [UTType] { [.markdown] }
    static var writableContentTypes: [UTType] { [.markdown] }

    init() {
        self.text = ""
    }

    convenience init(data: Data) throws {
        self.init()
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> Data {
        try dataForSaving()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    func dataForSaving() throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
