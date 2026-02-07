import Foundation

/// Exports markdown content to a standalone HTML file with all CSS inlined.
final class HTMLExporter {

    private let htmlGenerator = PreviewHTMLGenerator()

    /// Generates a complete, standalone HTML document from the given markdown
    /// and returns it as UTF-8 encoded data.
    func exportHTML(from markdown: String, darkMode: Bool) -> Data {
        let html = htmlGenerator.generateFullDocument(from: markdown, darkMode: darkMode)
        return Data(html.utf8)
    }
}
