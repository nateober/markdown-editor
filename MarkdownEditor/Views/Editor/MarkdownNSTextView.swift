import AppKit

class MarkdownNSTextView: NSTextView {

    convenience init(textStorage: MarkdownTextStorage) {
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.addTextContainer(textContainer)

        self.init(frame: .zero, textContainer: textContainer)
        configureDefaults()
        // Re-enable rich text so syntax highlighting attributes are rendered
        isRichText = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureDefaults()
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDefaults()
    }

    private func configureDefaults() {
        font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isRichText = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainerInset = NSSize(width: 20, height: 20)
        autoresizingMask = [.width]

        if let textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(
                width: bounds.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
    }
}
