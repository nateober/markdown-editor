import SwiftUI

struct SideBySideView: View {
    @Binding var text: String
    let htmlBody: String
    let baseURL: URL?
    var fontSize: Double = 14
    var vimEnabled: Bool = false
    var onCursorChange: ((Int, Int) -> Void)?
    var onVimModeChange: ((VimMode) -> Void)?

    var body: some View {
        HSplitView {
            MarkdownTextView(text: $text, fontSize: fontSize, vimEnabled: vimEnabled,
                             onCursorChange: onCursorChange, onVimModeChange: onVimModeChange)
                .frame(minWidth: 200)
            PreviewWebView(htmlBody: htmlBody, baseURL: baseURL)
                .frame(minWidth: 200)
        }
    }
}
