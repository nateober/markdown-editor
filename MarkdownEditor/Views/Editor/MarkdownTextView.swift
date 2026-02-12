import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double = 14
    var vimEnabled: Bool = false
    var onCursorChange: ((Int, Int) -> Void)?
    var onVimModeChange: ((VimMode) -> Void)?

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

        // Wire vim mode change callback
        let coordinator = context.coordinator
        textView.onVimModeChanged = { [weak coordinator] mode in
            coordinator?.onVimModeChange?(mode)
        }

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

        // Update callbacks
        let coordinator = context.coordinator
        coordinator.onCursorChange = onCursorChange
        coordinator.onVimModeChange = onVimModeChange
        textView.onVimModeChanged = { [weak coordinator] mode in
            coordinator?.onVimModeChange?(mode)
        }

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
        var onCursorChange: ((Int, Int) -> Void)?
        var onVimModeChange: ((VimMode) -> Void)?
        private var lastReportedMode: VimMode = .normal

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let nsString = textView.string as NSString
            let cursorLoc = textView.selectedRange().location
            let safeLoc = min(cursorLoc, nsString.length)

            let prefix = nsString.substring(to: safeLoc)
            let lines = prefix.components(separatedBy: "\n")
            let line = lines.count
            let column = (lines.last?.count ?? 0) + 1

            onCursorChange?(line, column)

            // Check vim mode
            if let mdTextView = textView as? MarkdownNSTextView {
                let currentMode = mdTextView.vimHandler.mode
                if currentMode != lastReportedMode {
                    lastReportedMode = currentMode
                    onVimModeChange?(currentMode)
                }
            }
        }
    }
}
