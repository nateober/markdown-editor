import AppKit

/// Exports markdown content to DOCX format using NSAttributedString's
/// built-in Office Open XML export capabilities.
final class DOCXExporter {

    enum ExportError: LocalizedError {
        case htmlConversionFailed
        case docxCreationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .htmlConversionFailed:
                return "Failed to convert markdown to attributed string for DOCX export."
            case .docxCreationFailed(let underlying):
                return "DOCX creation failed: \(underlying.localizedDescription)"
            }
        }
    }

    private let parser = MarkdownParser()

    /// Converts the given markdown to a DOCX document.
    ///
    /// The process is:
    /// 1. Parse markdown to HTML using MarkdownParser
    /// 2. Convert HTML to NSAttributedString
    /// 3. Export the attributed string as Office Open XML (.docx)
    func exportDOCX(from markdown: String) throws -> Data {
        let html = parser.parse(markdown)

        // Wrap in a minimal HTML document for proper NSAttributedString parsing
        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.6;
        }
        code {
            font-family: "SF Mono", Menlo, monospace;
            font-size: 12px;
            background-color: #f5f5f5;
            padding: 2px 4px;
            border-radius: 3px;
        }
        pre code {
            display: block;
            padding: 12px;
        }
        blockquote {
            border-left: 4px solid #ddd;
            padding-left: 16px;
            color: #555;
        }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """

        guard let htmlData = fullHTML.data(using: .utf8),
              let attributedString = NSAttributedString(
                html: htmlData,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            throw ExportError.htmlConversionFailed
        }

        let range = NSRange(location: 0, length: attributedString.length)

        do {
            let docxData = try attributedString.data(
                from: range,
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.officeOpenXML
                ]
            )
            return docxData
        } catch {
            throw ExportError.docxCreationFailed(error)
        }
    }
}
