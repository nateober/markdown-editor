import SwiftUI

struct SideBySideView: View {
    @Binding var text: String
    let htmlBody: String
    let baseURL: URL?

    var body: some View {
        HSplitView {
            MarkdownTextView(text: $text)
                .frame(minWidth: 200)
            PreviewWebView(htmlBody: htmlBody, baseURL: baseURL)
                .frame(minWidth: 200)
        }
    }
}
