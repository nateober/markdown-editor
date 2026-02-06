import AppKit

struct HighlightStyle {
    let foregroundColor: NSColor
    let font: NSFont?
    let backgroundColor: NSColor?
    let strikethrough: Bool
    let underline: Bool

    init(
        foreground: NSColor,
        font: NSFont? = nil,
        background: NSColor? = nil,
        strikethrough: Bool = false,
        underline: Bool = false
    ) {
        self.foregroundColor = foreground
        self.font = font
        self.backgroundColor = background
        self.strikethrough = strikethrough
        self.underline = underline
    }

    var attributes: [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: foregroundColor
        ]
        if let font { attrs[.font] = font }
        if let backgroundColor { attrs[.backgroundColor] = backgroundColor }
        if strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attrs
    }
}

struct HighlightTheme {
    let defaultStyle: HighlightStyle
    let heading1: HighlightStyle
    let heading2: HighlightStyle
    let heading3: HighlightStyle
    let heading4Plus: HighlightStyle
    let bold: HighlightStyle
    let italic: HighlightStyle
    let strikethrough: HighlightStyle
    let inlineCode: HighlightStyle
    let codeBlock: HighlightStyle
    let codeBlockFence: HighlightStyle
    let link: HighlightStyle
    let linkURL: HighlightStyle
    let image: HighlightStyle
    let blockquote: HighlightStyle
    let listMarker: HighlightStyle
    let horizontalRule: HighlightStyle
    let htmlTag: HighlightStyle
    let frontMatter: HighlightStyle
    let math: HighlightStyle
    let headingMarker: HighlightStyle

    static let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static let baseBoldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

    static var light: HighlightTheme {
        let text = NSColor(calibratedWhite: 0.15, alpha: 1)
        let muted = NSColor(calibratedWhite: 0.55, alpha: 1)

        return HighlightTheme(
            defaultStyle: HighlightStyle(foreground: text, font: baseFont),
            heading1: HighlightStyle(foreground: text, font: .monospacedSystemFont(ofSize: 24, weight: .bold)),
            heading2: HighlightStyle(foreground: text, font: .monospacedSystemFont(ofSize: 20, weight: .bold)),
            heading3: HighlightStyle(foreground: text, font: .monospacedSystemFont(ofSize: 17, weight: .bold)),
            heading4Plus: HighlightStyle(foreground: text, font: baseBoldFont),
            bold: HighlightStyle(foreground: text, font: baseBoldFont),
            italic: HighlightStyle(foreground: text),
            strikethrough: HighlightStyle(foreground: muted, strikethrough: true),
            inlineCode: HighlightStyle(foreground: NSColor.systemRed, background: NSColor(calibratedWhite: 0.94, alpha: 1)),
            codeBlock: HighlightStyle(foreground: text, font: baseFont, background: NSColor(calibratedWhite: 0.96, alpha: 1)),
            codeBlockFence: HighlightStyle(foreground: muted),
            link: HighlightStyle(foreground: NSColor.systemBlue, underline: true),
            linkURL: HighlightStyle(foreground: muted),
            image: HighlightStyle(foreground: NSColor.systemPurple),
            blockquote: HighlightStyle(foreground: muted),
            listMarker: HighlightStyle(foreground: NSColor.systemOrange),
            horizontalRule: HighlightStyle(foreground: muted),
            htmlTag: HighlightStyle(foreground: NSColor.systemTeal),
            frontMatter: HighlightStyle(foreground: muted),
            math: HighlightStyle(foreground: NSColor.systemGreen),
            headingMarker: HighlightStyle(foreground: muted)
        )
    }

    static var dark: HighlightTheme {
        let text = NSColor(calibratedWhite: 0.85, alpha: 1)
        let muted = NSColor(calibratedWhite: 0.5, alpha: 1)

        return HighlightTheme(
            defaultStyle: HighlightStyle(foreground: text, font: baseFont),
            heading1: HighlightStyle(foreground: text, font: .monospacedSystemFont(ofSize: 24, weight: .bold)),
            heading2: HighlightStyle(foreground: text, font: .monospacedSystemFont(ofSize: 20, weight: .bold)),
            heading3: HighlightStyle(foreground: text, font: .monospacedSystemFont(ofSize: 17, weight: .bold)),
            heading4Plus: HighlightStyle(foreground: text, font: baseBoldFont),
            bold: HighlightStyle(foreground: text, font: baseBoldFont),
            italic: HighlightStyle(foreground: text),
            strikethrough: HighlightStyle(foreground: muted, strikethrough: true),
            inlineCode: HighlightStyle(foreground: NSColor.systemPink, background: NSColor(calibratedWhite: 0.15, alpha: 1)),
            codeBlock: HighlightStyle(foreground: text, font: baseFont, background: NSColor(calibratedWhite: 0.1, alpha: 1)),
            codeBlockFence: HighlightStyle(foreground: muted),
            link: HighlightStyle(foreground: NSColor.systemBlue, underline: true),
            linkURL: HighlightStyle(foreground: muted),
            image: HighlightStyle(foreground: NSColor.systemPurple),
            blockquote: HighlightStyle(foreground: muted),
            listMarker: HighlightStyle(foreground: NSColor.systemOrange),
            horizontalRule: HighlightStyle(foreground: muted),
            htmlTag: HighlightStyle(foreground: NSColor.systemTeal),
            frontMatter: HighlightStyle(foreground: muted),
            math: HighlightStyle(foreground: NSColor.systemGreen),
            headingMarker: HighlightStyle(foreground: muted)
        )
    }

    static func current(for appearance: NSAppearance? = NSApp.effectiveAppearance) -> HighlightTheme {
        let isDark = appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .dark : .light
    }
}
