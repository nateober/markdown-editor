import SwiftUI

struct ToggleView: View {
    @Binding var text: String
    let htmlBody: String
    let baseURL: URL?
    let showingPreview: Bool

    var body: some View {
        ZStack {
            MarkdownTextView(text: $text)
                .opacity(showingPreview ? 0 : 1)
            PreviewWebView(htmlBody: htmlBody, baseURL: baseURL)
                .opacity(showingPreview ? 1 : 0)
        }
    }
}
