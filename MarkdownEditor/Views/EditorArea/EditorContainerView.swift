import SwiftUI

struct EditorContainerView: View {
    @Binding var text: String
    let viewMode: ViewMode
    let htmlBody: String
    let baseURL: URL?
    var fontSize: Double = 14
    var vimEnabled: Bool = false

    var body: some View {
        switch viewMode {
        case .sideBySide:
            SideBySideView(
                text: $text,
                htmlBody: htmlBody,
                baseURL: baseURL,
                fontSize: fontSize,
                vimEnabled: vimEnabled
            )
        case .editorOnly:
            MarkdownTextView(text: $text, fontSize: fontSize, vimEnabled: vimEnabled)
        case .previewOnly:
            PreviewWebView(htmlBody: htmlBody, baseURL: baseURL)
        }
    }
}
