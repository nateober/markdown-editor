import SwiftUI

struct SideBySideView: View {
    @Binding var text: String
    let htmlBody: String
    let baseURL: URL?
    var fontSize: Double = 14
    var vimEnabled: Bool = false

    var body: some View {
        HSplitView {
            MarkdownTextView(text: $text, fontSize: fontSize, vimEnabled: vimEnabled)
                .frame(minWidth: 200)
            PreviewWebView(htmlBody: htmlBody, baseURL: baseURL)
                .frame(minWidth: 200)
        }
    }
}
