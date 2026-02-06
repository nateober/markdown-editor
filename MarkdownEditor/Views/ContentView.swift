import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        MarkdownTextView(text: $document.text)
            .frame(minWidth: 600, minHeight: 400)
    }
}
