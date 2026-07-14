import AppKit
import WebKit

/// Exports markdown content to PDF by rendering it in an off-screen WKWebView
/// and using the native `createPDF` API.
@MainActor
final class PDFExporter: NSObject {

    enum ExportError: LocalizedError {
        case webViewLoadFailed
        case pdfCreationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .webViewLoadFailed:
                return "Failed to load content in web view for PDF export."
            case .pdfCreationFailed(let underlying):
                return "PDF creation failed: \(underlying.localizedDescription)"
            }
        }
    }

    private let htmlGenerator = PreviewHTMLGenerator()

    /// Renders the given markdown as a full HTML document in an off-screen WKWebView,
    /// waits for the page to finish loading, then creates and returns the PDF data.
    /// `baseURL` (the source document's folder) lets relative image paths resolve.
    func exportPDF(from markdown: String, darkMode: Bool, baseURL: URL? = nil) async throws -> Data {
        let html = htmlGenerator.generateFullDocument(from: markdown, darkMode: darkMode)

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")

        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        // With a baseURL, write the HTML to a hidden temp file inside that
        // folder and use loadFileURL(allowingReadAccessTo:) — WKWebView does
        // not grant local-file subresource access to string-loaded content,
        // so relative images would silently come out missing.
        var tempFileURL: URL?
        if let baseURL {
            let temp = baseURL.appendingPathComponent(".markdown-export-\(UUID().uuidString).html")
            if (try? html.write(to: temp, atomically: true, encoding: .utf8)) != nil {
                tempFileURL = temp
                webView.loadFileURL(temp, allowingReadAccessTo: baseURL)
            }
        }
        if tempFileURL == nil {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
        defer {
            if let tempFileURL {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }

        // Wait for the page to finish loading
        let didLoad = await withCheckedContinuation { continuation in
            delegate.completion = { success in
                continuation.resume(returning: success)
            }
        }
        // The webView only holds the delegate weakly; this keeps it alive
        // across the await without shared state (which would break if two
        // exports ever overlapped).
        withExtendedLifetime(delegate) {}

        guard didLoad else {
            throw ExportError.webViewLoadFailed
        }

        // Small delay to let any final rendering complete
        try? await Task.sleep(for: .milliseconds(100))

        do {
            let pdfData = try await webView.pdf()
            return pdfData
        } catch {
            throw ExportError.pdfCreationFailed(error)
        }
    }
}

// MARK: - Navigation Delegate

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    /// Called exactly once with the load outcome; multiple WebKit callbacks
    /// must not resume the awaiting continuation twice.
    var completion: ((Bool) -> Void)?

    private func finish(_ success: Bool) {
        let completion = self.completion
        self.completion = nil
        completion?(success)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(false)
    }
}
