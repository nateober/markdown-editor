import Testing
import Foundation
import WebKit
@testable import MarkdownEditor

/// Regression tests for the KaTeX delimiter behavior in the live preview.
/// A single `$...$` must NOT be treated as math (it ate prices/$VARs), while
/// `\(...\)` inline math and `$$...$$` display math must still render.
@Suite("PreviewMathRendering", .serialized)
struct PreviewMathRenderingTests {
    let parser = MarkdownParser()

    func jsEscape(_ html: String) -> String {
        html.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    @MainActor
    final class Harness: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        var onLoad: (() -> Void)?
        override init() {
            webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600),
                                configuration: WKWebViewConfiguration())
            super.init()
            webView.navigationDelegate = self
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onLoad?() }
    }

    @MainActor
    func render(_ markdown: String) async throws -> (text: String, hasKaTeX: Bool) {
        guard let url = Bundle.module.url(forResource: "preview", withExtension: "html", subdirectory: "Resources") else {
            throw NSError(domain: "test", code: 1)
        }
        let harness = Harness()
        await withCheckedContinuation { cont in
            harness.onLoad = { cont.resume() }
            harness.webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        let escaped = jsEscape(parser.parse(markdown))
        _ = try? await harness.webView.evaluateJavaScript("updateContent(`\(escaped)`)")
        try await Task.sleep(nanoseconds: 300_000_000)
        let text = (try? await harness.webView.evaluateJavaScript(
            "document.getElementById('content').innerText.trim()")) as? String ?? "<nil>"
        let hasKaTeX = ((try? await harness.webView.evaluateJavaScript(
            "document.querySelectorAll('#content .katex').length")) as? Int ?? 0) > 0
        return (text, hasKaTeX)
    }

    @MainActor
    @Test("Single $ in prose renders literally (prices, not math)")
    func dollarsInProseAreLiteral() async throws {
        let r = try await render("Tickets cost $5 and $10 please")
        #expect(r.text == "Tickets cost $5 and $10 please")
        #expect(r.hasKaTeX == false)
    }

    @MainActor
    @Test("Price range with em dash renders literally")
    func priceRangeLiteral() async throws {
        let r = try await render("Tickets are $5\u{2014}$10")
        #expect(r.text == "Tickets are $5\u{2014}$10")
        #expect(r.hasKaTeX == false)
    }

    @MainActor
    @Test("Guarded inline math $...$ renders when it looks like math")
    func inlineMathStillWorks() async throws {
        let r = try await render("Energy is $E = mc^2$ exactly")
        #expect(r.hasKaTeX == true)
        #expect(r.text.contains("$") == false)  // delimiters consumed, not literal
    }

    @MainActor
    @Test("Digit-adjacent $ stays literal (documents the price tradeoff)")
    func digitAdjacentDollarIsLiteral() async throws {
        let r = try await render("Costs $5 to make")
        #expect(r.text == "Costs $5 to make")
        #expect(r.hasKaTeX == false)
    }

    @MainActor
    @Test("Display math via $$...$$ still renders")
    func displayMathStillWorks() async throws {
        let r = try await render("$$\\int_0^1 x\\,dx$$")
        #expect(r.hasKaTeX == true)
    }
}
