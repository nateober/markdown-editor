import SwiftUI
import WebKit

struct PreviewWebView: NSViewRepresentable {
    private static let resourceBundle: Bundle = {
        let bundleName = "MarkdownEditor_MarkdownEditor"
        // SPM's Bundle.module checks Bundle.main.bundleURL (the .app root), which fails
        // code signing. Check Contents/Resources/ where the build script places it.
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent(bundleName + ".bundle"),
            Bundle.main.resourceURL?.appendingPathComponent(bundleName + ".bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/" + bundleName + ".bundle"),
        ].compactMap { $0 }
        for candidate in candidates {
            if let bundle = Bundle(url: candidate) {
                return bundle
            }
        }
        // Fall back to SPM's Bundle.module (works during swift build/test)
        return Bundle.module
    }()

    let htmlBody: String
    let baseURL: URL?

    init(htmlBody: String, baseURL: URL? = nil) {
        self.htmlBody = htmlBody
        self.baseURL = baseURL
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Load the preview template from bundle resources
        if let templateURL = Self.resourceBundle.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") {
            webView.loadFileURL(templateURL, allowingReadAccessTo: templateURL.deletingLastPathComponent())
        } else {
            // Fallback: minimal inline template
            let fallback = """
            <html><head><meta charset="utf-8">
            <style>body { font-family: -apple-system, sans-serif; padding: 24px; max-width: 800px; margin: 0 auto; }</style>
            </head><body><div id="content"></div>
            <script>
            function updateContent(html) {
                var el = document.getElementById('content');
                el.textContent = '';
                var temp = document.createElement('div');
                temp.innerHTML = html;
                while (temp.firstChild) { el.appendChild(temp.firstChild); }
            }
            </script>
            </body></html>
            """
            webView.loadHTMLString(fallback, baseURL: baseURL)
        }

        context.coordinator.pendingHTML = htmlBody
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let escaped = htmlBody
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        if context.coordinator.isLoaded {
            webView.evaluateJavaScript("updateContent(`\(escaped)`)")
        } else {
            context.coordinator.pendingHTML = htmlBody
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var isLoaded = false
        var pendingHTML: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let html = pendingHTML {
                let escaped = html
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                webView.evaluateJavaScript("updateContent(`\(escaped)`)")
                pendingHTML = nil
            }
        }
    }
}
