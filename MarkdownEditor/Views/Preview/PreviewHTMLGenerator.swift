import Foundation

final class PreviewHTMLGenerator {
    private let parser = MarkdownParser()

    func generateBody(from markdown: String) -> String {
        parser.parse(markdown)
    }

    func generateFullDocument(from markdown: String, darkMode: Bool) -> String {
        let body = generateBody(from: markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 24px;
                }
            </style>
        </head>
        <body>
            <div id="content">\(body)</div>
        </body>
        </html>
        """
    }
}
