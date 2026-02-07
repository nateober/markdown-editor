import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double = 14
    var vimEnabled: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let storage = MarkdownTextStorage()
        let textView = MarkdownNSTextView(textStorage: storage)
        textView.delegate = context.coordinator

        // Apply settings
        textView.font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        textView.vimEnabled = vimEnabled

        // Enable the use of the find bar (native NSTextView find panel)
        textView.isIncrementalSearchingEnabled = true
        textView.usesFindBar = true

        // Set initial text via the storage
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }

        // Update settings
        let newFont = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        if textView.font != newFont {
            textView.font = newFont
        }
        textView.vimEnabled = vimEnabled

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            if let storage = textView.textStorage {
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
            }
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: MarkdownNSTextView?

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
