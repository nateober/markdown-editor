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
        self.text = try Self.decode(data)
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = try Self.decode(data)
    }

    private static func decode(_ data: Data) throws -> String {
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Strip a leading UTF-8 BOM (common in Windows-authored files); left in
        // place it breaks parsing of the first line (e.g. a leading heading).
        if string.hasPrefix("\u{FEFF}") {
            return String(string.dropFirst())
        }
        return string
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
