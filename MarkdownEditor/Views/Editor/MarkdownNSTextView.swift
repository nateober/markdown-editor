import AppKit
import UniformTypeIdentifiers

class MarkdownNSTextView: NSTextView {

    // MARK: - Image Properties

    /// The URL of the document currently being edited.
    /// Must be set (i.e. the document must be saved to disk) before images can be pasted or dropped.
    var documentURL: URL?

    /// The image manager used for saving pasted / dropped images.
    let imageManager = ImageManager()

    // MARK: - Vim Properties

    /// When true, key events are routed through VimInputHandler.
    var vimEnabled: Bool = false

    /// The Vim input handler (state machine).
    let vimHandler = VimInputHandler()

    /// Called when the vim mode changes (from key handling).
    var onVimModeChanged: ((VimMode) -> Void)?

    /// Tracks the last known mode to detect changes.
    private var lastKnownVimMode: VimMode = .normal

    /// The Vim motion executor.
    private let vimMotionExecutor = VimMotionExecutor()

    /// The yank register (clipboard for vim operations).
    private(set) var yankRegister: String = ""

    /// Whether the yank register contains a full line (for line-wise paste).
    private(set) var yankIsLinewise: Bool = false

    // MARK: - Initializers

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

    // MARK: - Appearance Change

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rehighlightAllText()
    }

    func rehighlightAllText() {
        guard let storage = textStorage as? MarkdownTextStorage else { return }
        storage.rehighlight()
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
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 20, height: 20)
        autoresizingMask = [.width]

        if let textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(
                width: bounds.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        }

        // Register for image drag types.
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    // MARK: - Key Handling

    override func keyDown(with event: NSEvent) {
        guard vimEnabled else {
            super.keyDown(with: event)
            return
        }

        // Convert NSEvent modifier flags to VimKeyModifiers
        let modifiers = vimKeyModifiers(from: event.modifierFlags)

        // Get the character from the event
        guard let characters = event.charactersIgnoringModifiers,
              let key = characters.first else {
            super.keyDown(with: event)
            return
        }

        let result = vimHandler.handleKey(key, modifiers: modifiers)
        dispatchVimResult(result, event: event)
    }

    private func vimKeyModifiers(from flags: NSEvent.ModifierFlags) -> VimKeyModifiers {
        var modifiers: VimKeyModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    // MARK: - VimResult Dispatch

    private func dispatchVimResult(_ result: VimResult, event: NSEvent) {
        let isVisual = vimHandler.mode == .visual || vimHandler.mode == .visualLine

        defer { checkVimModeChange() }

        switch result {
        case .pending:
            // Waiting for more input; do nothing.
            break

        case .passthrough:
            // Let the text view handle it normally (insert mode).
            super.keyDown(with: event)

        case .modeChange(let mode):
            // Mode change is handled by the handler itself.
            // We could update UI indicators here in the future.
            if mode == .normal {
                // When returning to normal mode, collapse selection
                let loc = selectedRange().location
                setSelectedRange(NSRange(location: loc, length: 0))
            }
            break

        case .motion(let motion, let count):
            vimMotionExecutor.executeMotion(motion, on: self, count: count, extending: isVisual)

        case .operatorMotion(let op, let motion, let count):
            executeOperatorMotion(op, motion: motion, count: count)

        case .operatorLine(let op, let count):
            executeOperatorLine(op, count: count)

        case .deleteChar(let count):
            for _ in 0..<count {
                deleteForward(nil)
            }

        case .deleteCharBefore(let count):
            for _ in 0..<count {
                deleteBackward(nil)
            }

        case .replaceChar(let ch):
            let range = selectedRange()
            if range.location < (string as NSString).length {
                let replaceRange = NSRange(location: range.location, length: 1)
                if shouldChangeText(in: replaceRange, replacementString: String(ch)) {
                    textStorage?.replaceCharacters(in: replaceRange, with: String(ch))
                    didChangeText()
                    setSelectedRange(NSRange(location: range.location, length: 0))
                }
            }

        case .pasteAfter:
            pasteFromYankRegister(after: true)

        case .pasteBefore:
            pasteFromYankRegister(after: false)

        case .undo:
            undoManager?.undo()

        case .redo:
            undoManager?.redo()

        case .repeatLastChange:
            if let lastResult = vimHandler.lastChangeResult {
                dispatchVimResult(lastResult, event: event)
                if let insertText = vimHandler.lastChangeInsertText, !insertText.isEmpty {
                    dispatchVimResult(.replayInsert(insertText), event: event)
                }
            }

        case .operatorTextObject(let op, let textObj, _):
            executeOperatorTextObject(op, textObject: textObj)

        case .replayInsert(let text):
            let range = selectedRange()
            if shouldChangeText(in: range, replacementString: text) {
                textStorage?.replaceCharacters(in: range, with: text)
                didChangeText()
                setSelectedRange(NSRange(location: range.location + text.count, length: 0))
            }
            vimHandler.reset()

        case .joinLines:
            joinCurrentLineWithNext()

        case .openLineBelow:
            moveToEndOfLine(nil)
            insertNewline(nil)

        case .openLineAbove:
            moveToBeginningOfLine(nil)
            insertNewline(nil)
            moveUp(nil)

        case .insertAfterCursor:
            moveForward(nil)

        case .insertAtEndOfLine:
            moveToEndOfLine(nil)

        case .insertAtLineStart:
            moveToBeginningOfLine(nil)
            // Skip whitespace
            let nsString = string as NSString
            var loc = selectedRange().location
            while loc < nsString.length {
                let ch = nsString.character(at: loc)
                if ch == 0x20 || ch == 0x09 {
                    moveForward(nil)
                    loc += 1
                } else {
                    break
                }
            }

        case .searchForward:
            // Search would require a search UI; for now, trigger the find panel.
            performFindPanelAction(nil)
        }
    }

    private func checkVimModeChange() {
        let currentMode = vimHandler.mode
        if currentMode != lastKnownVimMode {
            lastKnownVimMode = currentMode
            onVimModeChanged?(currentMode)
        }
    }

    // MARK: - Operator Execution

    private func executeOperatorMotion(_ op: VimOperator, motion: VimMotion, count: Int) {
        let range = vimMotionExecutor.rangeForMotion(motion, on: self, count: count)

        guard range.length > 0 else { return }

        switch op {
        case .delete:
            yankText(in: range, linewise: false)
            deleteText(in: range)

        case .change:
            yankText(in: range, linewise: false)
            deleteText(in: range)
            // The handler already switched to insert mode

        case .yank:
            yankText(in: range, linewise: false)

        case .indent:
            indentLines(in: range)

        case .outdent:
            outdentLines(in: range)
        }
    }

    private func executeOperatorLine(_ op: VimOperator, count: Int) {
        let range = vimMotionExecutor.rangeForLines(on: self, count: count)

        guard range.length > 0 else { return }

        switch op {
        case .delete:
            yankText(in: range, linewise: true)
            deleteText(in: range)

        case .change:
            yankText(in: range, linewise: true)
            deleteText(in: range)
            // Handler already switched to insert mode

        case .yank:
            yankText(in: range, linewise: true)

        case .indent:
            indentLines(in: range)

        case .outdent:
            outdentLines(in: range)
        }
    }

    private func executeOperatorTextObject(_ op: VimOperator, textObject: VimTextObject) {
        guard let range = rangeForTextObject(textObject) else { return }
        guard range.length > 0 else { return }

        switch op {
        case .delete:
            yankText(in: range, linewise: false)
            deleteText(in: range)

        case .change:
            yankText(in: range, linewise: false)
            deleteText(in: range)

        case .yank:
            yankText(in: range, linewise: false)

        case .indent:
            indentLines(in: range)

        case .outdent:
            outdentLines(in: range)
        }
    }

    private func rangeForTextObject(_ textObject: VimTextObject) -> NSRange? {
        let nsString = string as NSString
        let cursorLoc = selectedRange().location

        switch textObject {
        case .innerWord:
            return wordRange(at: cursorLoc, in: nsString, around: false)
        case .aroundWord:
            return wordRange(at: cursorLoc, in: nsString, around: true)
        case .inner(let delimiter):
            return delimiterRange(at: cursorLoc, in: nsString, delimiter: delimiter, around: false)
        case .around(let delimiter):
            return delimiterRange(at: cursorLoc, in: nsString, delimiter: delimiter, around: true)
        }
    }

    private func wordRange(at pos: Int, in string: NSString, around: Bool) -> NSRange? {
        guard pos < string.length else { return nil }

        let isWordChar: (unichar) -> Bool = { ch in
            (ch >= 0x30 && ch <= 0x39) || (ch >= 0x41 && ch <= 0x5A) ||
            (ch >= 0x61 && ch <= 0x7A) || ch == 0x5F
        }

        let ch = string.character(at: pos)
        let isWord = isWordChar(ch)
        let isWhitespace = ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D

        // Find start of word
        var start = pos
        while start > 0 {
            let prev = string.character(at: start - 1)
            if isWhitespace {
                if !(prev == 0x20 || prev == 0x09 || prev == 0x0A || prev == 0x0D) { break }
            } else if isWord {
                if !isWordChar(prev) { break }
            } else {
                let prevIsWhitespace = prev == 0x20 || prev == 0x09 || prev == 0x0A || prev == 0x0D
                if prevIsWhitespace || isWordChar(prev) { break }
            }
            start -= 1
        }

        // Find end of word
        var end = pos
        while end + 1 < string.length {
            let next = string.character(at: end + 1)
            if isWhitespace {
                if !(next == 0x20 || next == 0x09 || next == 0x0A || next == 0x0D) { break }
            } else if isWord {
                if !isWordChar(next) { break }
            } else {
                let nextIsWhitespace = next == 0x20 || next == 0x09 || next == 0x0A || next == 0x0D
                if nextIsWhitespace || isWordChar(next) { break }
            }
            end += 1
        }

        if around {
            // Include trailing whitespace
            while end + 1 < string.length {
                let next = string.character(at: end + 1)
                if next == 0x20 || next == 0x09 {
                    end += 1
                } else {
                    break
                }
            }
        }

        return NSRange(location: start, length: end - start + 1)
    }

    private func delimiterRange(at pos: Int, in string: NSString, delimiter: Character, around: Bool) -> NSRange? {
        guard let delimScalar = delimiter.unicodeScalars.first else { return nil }
        let delimValue = delimScalar.value

        let pairs: [(Character, Character)] = [("(", ")"), ("{", "}"), ("[", "]")]

        // Check if this is a paired delimiter
        for (open, close) in pairs {
            if delimiter == open {
                return pairedDelimiterRange(at: pos, in: string,
                                            open: open.unicodeScalars.first!.value,
                                            close: close.unicodeScalars.first!.value,
                                            around: around)
            }
        }

        // Quote-style delimiter: scan both directions
        // Find the opening delimiter (search backward)
        var openPos: Int? = nil
        for i in stride(from: pos, through: 0, by: -1) {
            if string.character(at: i) == delimValue {
                // Check it's not escaped
                if i == 0 || string.character(at: i - 1) != 0x5C { // backslash
                    openPos = i
                    break
                }
            }
        }

        guard let open = openPos else { return nil }

        // Find closing delimiter (search forward from after open)
        let searchStart = (open == pos) ? open + 1 : pos
        var closePos: Int? = nil
        for i in searchStart..<string.length {
            if i == open { continue }
            if string.character(at: i) == delimValue {
                if i == 0 || string.character(at: i - 1) != 0x5C {
                    closePos = i
                    break
                }
            }
        }

        guard let close = closePos else { return nil }

        if around {
            return NSRange(location: open, length: close - open + 1)
        } else {
            let innerStart = open + 1
            let innerLen = close - innerStart
            return innerLen > 0 ? NSRange(location: innerStart, length: innerLen) : NSRange(location: innerStart, length: 0)
        }
    }

    private func pairedDelimiterRange(at pos: Int, in string: NSString,
                                       open: UInt32, close: UInt32, around: Bool) -> NSRange? {
        // Search backward for opening delimiter
        var depth = 0
        var openPos: Int? = nil
        for i in stride(from: pos, through: 0, by: -1) {
            let ch = string.character(at: i)
            if ch == UInt16(close) { depth += 1 }
            else if ch == UInt16(open) {
                if depth == 0 {
                    openPos = i
                    break
                }
                depth -= 1
            }
        }

        guard let op = openPos else { return nil }

        // Search forward for closing delimiter
        depth = 0
        var closePos: Int? = nil
        for i in (op + 1)..<string.length {
            let ch = string.character(at: i)
            if ch == UInt16(open) { depth += 1 }
            else if ch == UInt16(close) {
                if depth == 0 {
                    closePos = i
                    break
                }
                depth -= 1
            }
        }

        guard let cl = closePos else { return nil }

        if around {
            return NSRange(location: op, length: cl - op + 1)
        } else {
            let innerStart = op + 1
            let innerLen = cl - innerStart
            return innerLen > 0 ? NSRange(location: innerStart, length: innerLen) : NSRange(location: innerStart, length: 0)
        }
    }

    // MARK: - Text Manipulation Helpers

    private func yankText(in range: NSRange, linewise: Bool) {
        let nsString = string as NSString
        guard range.location + range.length <= nsString.length else { return }
        yankRegister = nsString.substring(with: range)
        yankIsLinewise = linewise
    }

    private func deleteText(in range: NSRange) {
        if shouldChangeText(in: range, replacementString: "") {
            textStorage?.replaceCharacters(in: range, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: range.location, length: 0))
        }
    }

    private func pasteFromYankRegister(after: Bool) {
        guard !yankRegister.isEmpty else { return }

        if yankIsLinewise {
            if after {
                // Move to end of current line, insert newline + content
                moveToEndOfLine(nil)
                let insertLoc = selectedRange().location
                let textToInsert: String
                if yankRegister.hasSuffix("\n") {
                    textToInsert = "\n" + String(yankRegister.dropLast())
                } else {
                    textToInsert = "\n" + yankRegister
                }
                let range = NSRange(location: insertLoc, length: 0)
                if shouldChangeText(in: range, replacementString: textToInsert) {
                    textStorage?.replaceCharacters(in: range, with: textToInsert)
                    didChangeText()
                    // Position cursor at start of pasted text
                    setSelectedRange(NSRange(location: insertLoc + 1, length: 0))
                }
            } else {
                // Move to beginning of current line, insert content
                moveToBeginningOfLine(nil)
                let insertLoc = selectedRange().location
                let textToInsert: String
                if yankRegister.hasSuffix("\n") {
                    textToInsert = yankRegister
                } else {
                    textToInsert = yankRegister + "\n"
                }
                let range = NSRange(location: insertLoc, length: 0)
                if shouldChangeText(in: range, replacementString: textToInsert) {
                    textStorage?.replaceCharacters(in: range, with: textToInsert)
                    didChangeText()
                    setSelectedRange(NSRange(location: insertLoc, length: 0))
                }
            }
        } else {
            // Character-wise paste
            var insertLoc = selectedRange().location
            if after && (string as NSString).length > 0 {
                insertLoc = min(insertLoc + 1, (string as NSString).length)
            }
            let range = NSRange(location: insertLoc, length: 0)
            if shouldChangeText(in: range, replacementString: yankRegister) {
                textStorage?.replaceCharacters(in: range, with: yankRegister)
                didChangeText()
                setSelectedRange(NSRange(location: insertLoc + yankRegister.count - 1, length: 0))
            }
        }
    }

    private func joinCurrentLineWithNext() {
        let nsString = string as NSString
        let cursorLoc = selectedRange().location

        guard cursorLoc < nsString.length else { return }

        let lineRange = nsString.lineRange(for: NSRange(location: cursorLoc, length: 0))
        let endOfLine = NSMaxRange(lineRange)

        guard endOfLine < nsString.length else { return }

        // Find the newline character at end of current line
        // Remove the newline and any leading whitespace on the next line, replace with a space
        let nextLineRange = nsString.lineRange(for: NSRange(location: endOfLine, length: 0))
        let nextLineContent = nsString.substring(with: nextLineRange)
        let trimmedNext = nextLineContent.trimmingCharacters(in: .whitespaces)

        // The range to replace: from the newline before endOfLine to the start of actual content on next line
        let newlineStart = endOfLine - 1 // Position of '\n'
        let contentStart = nextLineRange.location + (nextLineContent.count - trimmedNext.count)
        // If next line is just a newline, handle that
        let replaceRangeLen = contentStart - newlineStart
        let replaceRange = NSRange(location: newlineStart, length: replaceRangeLen)

        let replacement = trimmedNext.isEmpty ? "" : " "
        if shouldChangeText(in: replaceRange, replacementString: replacement) {
            textStorage?.replaceCharacters(in: replaceRange, with: replacement)
            didChangeText()
            setSelectedRange(NSRange(location: newlineStart, length: 0))
        }
    }

    private func indentLines(in range: NSRange) {
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: range)
        let lines = nsString.substring(with: lineRange)
        let indented = lines.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    " + $0 }
            .joined(separator: "\n")

        if shouldChangeText(in: lineRange, replacementString: indented) {
            textStorage?.replaceCharacters(in: lineRange, with: indented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: 0))
        }
    }

    private func outdentLines(in range: NSRange) {
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: range)
        let lines = nsString.substring(with: lineRange)
        let outdented = lines.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = String(line)
                // Remove up to 4 leading spaces or 1 tab
                if s.hasPrefix("    ") {
                    s.removeFirst(4)
                } else if s.hasPrefix("\t") {
                    s.removeFirst(1)
                } else {
                    // Remove as many leading spaces as possible up to 4
                    var removed = 0
                    while s.hasPrefix(" ") && removed < 4 {
                        s.removeFirst(1)
                        removed += 1
                    }
                }
                return s
            }
            .joined(separator: "\n")

        if shouldChangeText(in: lineRange, replacementString: outdented) {
            textStorage?.replaceCharacters(in: lineRange, with: outdented)
            didChangeText()
            setSelectedRange(NSRange(location: lineRange.location, length: 0))
        }
    }

    // MARK: - Paste Override (Image Support)

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // Check for image data on the pasteboard first.
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            if let pngData = normalizeImageDataToPNG(imageData) {
                insertImageFromData(pngData)
                return
            }
        }

        // Fall through to default paste behaviour (text, etc.).
        super.paste(sender)
    }

    // MARK: - Drag & Drop (Image Support)

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard

        if pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFileReadingOptions())
            || pasteboard.types?.contains(.png) == true
            || pasteboard.types?.contains(.tiff) == true {
            return .copy
        }

        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        // 1. Try reading file URLs that are images.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: imageFileReadingOptions()) as? [URL],
           let firstURL = urls.first {
            return insertImageFromFileURL(firstURL, at: sender)
        }

        // 2. Try raw image data (e.g. dragged from another app).
        if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            if let pngData = normalizeImageDataToPNG(imageData) {
                // Set insertion point at the drop location.
                let dropPoint = convert(sender.draggingLocation, from: nil)
                let charIndex = characterIndexForInsertion(at: dropPoint)
                setSelectedRange(NSRange(location: charIndex, length: 0))
                insertImageFromData(pngData)
                return true
            }
        }

        return super.performDragOperation(sender)
    }

    // MARK: - Image Insertion Helpers

    /// Insert markdown image syntax for the given raw PNG data at the current cursor position.
    private func insertImageFromData(_ data: Data) {
        guard let docURL = documentURL else {
            showDocumentNotSavedAlert()
            return
        }

        guard let relativePath = imageManager.saveImage(data, relativeTo: docURL) else { return }
        insertMarkdownImageSyntax(relativePath)
    }

    /// Copy an image file into the images directory and insert markdown syntax at the drop location.
    private func insertImageFromFileURL(_ fileURL: URL, at sender: NSDraggingInfo) -> Bool {
        guard let docURL = documentURL else {
            showDocumentNotSavedAlert()
            return false
        }

        guard let relativePath = imageManager.copyImage(from: fileURL, relativeTo: docURL) else {
            return false
        }

        // Set insertion point at the drop location.
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let charIndex = characterIndexForInsertion(at: dropPoint)
        setSelectedRange(NSRange(location: charIndex, length: 0))

        insertMarkdownImageSyntax(relativePath)
        return true
    }

    /// Insert `![](path)` at the current selection / cursor position.
    private func insertMarkdownImageSyntax(_ relativePath: String) {
        let encoded = relativePath.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? relativePath
        let markdown = "![](\(encoded))"
        let insertRange = selectedRange()
        if shouldChangeText(in: insertRange, replacementString: markdown) {
            textStorage?.replaceCharacters(in: insertRange, with: markdown)
            didChangeText()
            setSelectedRange(NSRange(location: insertRange.location + markdown.count, length: 0))
        }
    }

    /// Convert any image data (TIFF, PNG, etc.) to PNG bytes.
    private func normalizeImageDataToPNG(_ data: Data) -> Data? {
        guard let imageRep = NSBitmapImageRep(data: data) else { return nil }
        return imageRep.representation(using: .png, properties: [:])
    }

    /// Options for reading file URLs that refer to image files.
    private func imageFileReadingOptions() -> [NSPasteboard.ReadingOptionKey: Any] {
        [
            .urlReadingContentsConformToTypes: [
                UTType.png.identifier,
                UTType.jpeg.identifier,
                UTType.tiff.identifier,
                UTType.gif.identifier,
                UTType.bmp.identifier,
                UTType.image.identifier,
            ]
        ]
    }

    /// Show an alert informing the user the document must be saved before images can be embedded.
    private func showDocumentNotSavedAlert() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Save Document First"
        alert.informativeText = "Please save this document to disk before pasting or dropping images. The images are stored in a folder next to the document file."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
