import SwiftUI

struct EditorContainerView: View {
    @Binding var text: String
    let viewMode: ViewMode
    let htmlBody: String
    let baseURL: URL?

    var body: some View {
        switch viewMode {
        case .sideBySide:
            SideBySideView(text: $text, htmlBody: htmlBody, baseURL: baseURL)
        case .editorOnly:
            MarkdownTextView(text: $text)
        case .previewOnly:
            PreviewWebView(htmlBody: htmlBody, baseURL: baseURL)
        }
    }
}
