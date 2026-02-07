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
    func exportPDF(from markdown: String, darkMode: Bool) async throws -> Data {
        let html = htmlGenerator.generateFullDocument(from: markdown, darkMode: darkMode)

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")

        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        webView.loadHTMLString(html, baseURL: nil)

        // Wait for the page to finish loading
        let didLoad = await withCheckedContinuation { continuation in
            delegate.onFinish = {
                continuation.resume(returning: true)
            }
            delegate.onFail = {
                continuation.resume(returning: false)
            }
        }

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
    var onFinish: (() -> Void)?
    var onFail: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFail?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onFail?()
    }
}
