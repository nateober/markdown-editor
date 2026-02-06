import AppKit

class MarkdownTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    private let highlighter = SyntaxHighlighter()

    override var string: String {
        backing.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        let theme = HighlightTheme.current()

        // Extend edited range to full paragraphs for correct multi-line highlighting
        let paragraphRange = (string as NSString).paragraphRange(for: editedRange)
        let safeRange = NSIntersectionRange(paragraphRange, NSRange(location: 0, length: length))

        if safeRange.length > 0 {
            // Reset to default style first, then apply highlighting
            // IMPORTANT: Modify backing directly to avoid infinite recursion
            backing.setAttributes(theme.defaultStyle.attributes, range: safeRange)
            highlighter.highlight(in: backing, range: safeRange, theme: theme)
        }

        super.processEditing()
    }
}
