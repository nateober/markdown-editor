import AppKit

final class SyntaxHighlighter {

    // MARK: - Compiled Patterns

    private struct Pattern {
        let regex: NSRegularExpression
        let apply: (NSMutableAttributedString, NSTextCheckingResult, HighlightTheme) -> Void
    }

    // Block-level patterns (order matters)
    private let frontMatterPattern: NSRegularExpression
    private let fencedCodeBlockPattern: NSRegularExpression

    // Inline/block patterns applied in priority order
    private let patterns: [(NSRegularExpression, (NSMutableAttributedString, NSTextCheckingResult, HighlightTheme) -> Void)]

    init() {
        // Front matter: must start at very beginning of string
        frontMatterPattern = try! NSRegularExpression(
            pattern: "\\A---\\n[\\s\\S]*?\\n---",
            options: []
        )

        // Fenced code blocks: ``` or ~~~ with optional language, through closing fence
        fencedCodeBlockPattern = try! NSRegularExpression(
            pattern: "^(`{3,}|~{3,})(\\w*)\\s*\\n[\\s\\S]*?^\\1\\s*$",
            options: [.anchorsMatchLines]
        )

        // Headings: # through ###### at start of line
        let headingPattern = try! NSRegularExpression(
            pattern: "^(#{1,6})\\s+(.+)$",
            options: [.anchorsMatchLines]
        )

        // Blockquote: > at start of line
        let blockquotePattern = try! NSRegularExpression(
            pattern: "^>\\s?(.*)$",
            options: [.anchorsMatchLines]
        )

        // Horizontal rule: three or more -, *, or _
        let hrPattern = try! NSRegularExpression(
            pattern: "^([-*_]){3,}\\s*$",
            options: [.anchorsMatchLines]
        )

        // List markers: -, *, +, or 1. with optional checkbox
        let listMarkerPattern = try! NSRegularExpression(
            pattern: "^(\\s*)([-*+]|\\d+\\.)\\s+(\\[[ xX]\\]\\s+)?",
            options: [.anchorsMatchLines]
        )

        // Bold: **text** or __text__
        let boldPattern = try! NSRegularExpression(
            pattern: "(\\*\\*|__)(.+?)\\1",
            options: []
        )

        // Italic with asterisk: *text* (not preceded or followed by *)
        let italicAsteriskPattern = try! NSRegularExpression(
            pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)",
            options: []
        )

        // Italic with underscore: _text_ (not preceded or followed by _)
        let italicUnderscorePattern = try! NSRegularExpression(
            pattern: "(?<!_)_(?!_)(.+?)(?<!_)_(?!_)",
            options: []
        )

        // Strikethrough: ~~text~~
        let strikethroughPattern = try! NSRegularExpression(
            pattern: "~~(.+?)~~",
            options: []
        )

        // Image: ![alt](url)
        let imagePattern = try! NSRegularExpression(
            pattern: "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)",
            options: []
        )

        // Link: [text](url)
        let linkPattern = try! NSRegularExpression(
            pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)",
            options: []
        )

        // Inline code: `code`
        let inlineCodePattern = try! NSRegularExpression(
            pattern: "(?<!`)`(?!`)(.+?)(?<!`)`(?!`)",
            options: []
        )

        // Math: $$...$$ (display) and $...$ (inline)
        let displayMathPattern = try! NSRegularExpression(
            pattern: "\\$\\$[\\s\\S]+?\\$\\$",
            options: []
        )

        let inlineMathPattern = try! NSRegularExpression(
            pattern: "(?<!\\$)\\$(?!\\$)(.+?)(?<!\\$)\\$(?!\\$)",
            options: []
        )

        // HTML tags
        let htmlTagPattern = try! NSRegularExpression(
            pattern: "</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?>",
            options: []
        )

        // Build the patterns array in priority order
        patterns = [
            (headingPattern, Self.applyHeading),
            (blockquotePattern, Self.applyBlockquote),
            (hrPattern, Self.applyHorizontalRule),
            (listMarkerPattern, Self.applyListMarker),
            (boldPattern, Self.applyBold),
            (italicAsteriskPattern, Self.applyItalic),
            (italicUnderscorePattern, Self.applyItalic),
            (strikethroughPattern, Self.applyStrikethrough),
            (imagePattern, Self.applyImage),
            (linkPattern, Self.applyLink),
            (inlineCodePattern, Self.applyInlineCode),
            (displayMathPattern, Self.applyMath),
            (inlineMathPattern, Self.applyMath),
            (htmlTagPattern, Self.applyHTMLTag),
        ]
    }

    // MARK: - Public API

    func highlight(in storage: NSMutableAttributedString, range: NSRange, theme: HighlightTheme) {
        let text = storage.string

        // Track code block ranges so inline patterns skip them
        var codeBlockRanges: [NSRange] = []

        // 1. Front matter (only at start of document)
        if range.location == 0 {
            frontMatterPattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let matchRange = match?.range else { return }
                storage.addAttributes(theme.frontMatter.attributes, range: matchRange)
                codeBlockRanges.append(matchRange)
            }
        }

        // 2. Fenced code blocks
        fencedCodeBlockPattern.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match else { return }
            let fullRange = match.range

            // Apply code block background to entire block
            storage.addAttributes(theme.codeBlock.attributes, range: fullRange)

            // Apply fence style to the opening and closing fence lines
            let nsText = text as NSString
            let blockStart = fullRange.location
            let firstLineEnd = nsText.range(
                of: "\n",
                options: [],
                range: NSRange(location: blockStart, length: fullRange.length)
            )
            if firstLineEnd.location != NSNotFound {
                let openFenceRange = NSRange(location: blockStart, length: firstLineEnd.location - blockStart)
                storage.addAttributes(theme.codeBlockFence.attributes, range: openFenceRange)
            }

            // Closing fence: find the last line of the block
            let blockEnd = NSMaxRange(fullRange)
            let lastNewline = nsText.range(
                of: "\n",
                options: .backwards,
                range: NSRange(location: blockStart, length: blockEnd - blockStart - 1)
            )
            if lastNewline.location != NSNotFound {
                let closeFenceRange = NSRange(location: lastNewline.location + 1, length: blockEnd - lastNewline.location - 1)
                if closeFenceRange.length > 0 {
                    storage.addAttributes(theme.codeBlockFence.attributes, range: closeFenceRange)
                }
            }

            codeBlockRanges.append(fullRange)
        }

        // 3. Apply inline/block patterns, skipping code block ranges
        for (regex, applier) in patterns {
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match else { return }
                let matchRange = match.range

                // Skip if this match falls inside a code block
                let insideCodeBlock = codeBlockRanges.contains { codeRange in
                    NSIntersectionRange(codeRange, matchRange).length == matchRange.length
                }
                if insideCodeBlock { return }

                applier(storage, match, theme)
            }
        }
    }

    // MARK: - Style Appliers

    private static func applyHeading(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        let markerRange = match.range(at: 1)
        let textRange = match.range(at: 2)
        let hashCount = markerRange.length

        let style: HighlightStyle
        switch hashCount {
        case 1: style = theme.heading1
        case 2: style = theme.heading2
        case 3: style = theme.heading3
        default: style = theme.heading4Plus
        }

        // Apply heading style to the text
        if textRange.location != NSNotFound {
            storage.addAttributes(style.attributes, range: textRange)
        }

        // Apply muted marker style to the "# " prefix
        if markerRange.location != NSNotFound {
            storage.addAttributes(theme.headingMarker.attributes, range: markerRange)
            // Also style the space between marker and text
            let spaceLocation = NSMaxRange(markerRange)
            if spaceLocation < textRange.location {
                let spaceRange = NSRange(location: spaceLocation, length: textRange.location - spaceLocation)
                storage.addAttributes(theme.headingMarker.attributes, range: spaceRange)
            }
        }
    }

    private static func applyBlockquote(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.blockquote.attributes, range: match.range)
    }

    private static func applyHorizontalRule(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.horizontalRule.attributes, range: match.range)
    }

    private static func applyListMarker(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        // Apply the orange color to the marker (group 2) and optional checkbox (group 3)
        let markerRange = match.range(at: 2)
        if markerRange.location != NSNotFound {
            storage.addAttributes(theme.listMarker.attributes, range: markerRange)
        }
        let checkboxRange = match.range(at: 3)
        if checkboxRange.location != NSNotFound {
            storage.addAttributes(theme.listMarker.attributes, range: checkboxRange)
        }
    }

    private static func applyBold(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.bold.attributes, range: match.range)
    }

    private static func applyItalic(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        let fullRange = match.range
        // Get the current font at this position and convert to italic
        let existingFont = storage.attribute(.font, at: fullRange.location, effectiveRange: nil) as? NSFont
            ?? HighlightTheme.baseFont
        let italicFont = NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
        var attrs = theme.italic.attributes
        attrs[.font] = italicFont
        storage.addAttributes(attrs, range: fullRange)
    }

    private static func applyStrikethrough(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.strikethrough.attributes, range: match.range)
    }

    private static func applyImage(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.image.attributes, range: match.range)
    }

    private static func applyLink(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        let fullRange = match.range
        let textRange = match.range(at: 1)
        let urlRange = match.range(at: 2)

        // Apply link style to the display text [text]
        if textRange.location != NSNotFound {
            storage.addAttributes(theme.link.attributes, range: textRange)
        }

        // Apply muted URL style to the (url) portion
        if urlRange.location != NSNotFound {
            storage.addAttributes(theme.linkURL.attributes, range: urlRange)
        }

        // Apply muted style to the brackets and parens
        let bracketOpen = NSRange(location: fullRange.location, length: 1)
        storage.addAttributes(theme.linkURL.attributes, range: bracketOpen)

        if textRange.location != NSNotFound {
            let bracketClose = NSRange(location: NSMaxRange(textRange), length: 1)
            storage.addAttributes(theme.linkURL.attributes, range: bracketClose)
        }
    }

    private static func applyInlineCode(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.inlineCode.attributes, range: match.range)
    }

    private static func applyMath(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.math.attributes, range: match.range)
    }

    private static func applyHTMLTag(
        _ storage: NSMutableAttributedString,
        _ match: NSTextCheckingResult,
        _ theme: HighlightTheme
    ) {
        storage.addAttributes(theme.htmlTag.attributes, range: match.range)
    }
}
