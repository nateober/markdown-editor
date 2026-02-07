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
            // Repeat last change is complex; for now, do nothing.
            // A full implementation would record and replay the last edit.
            break

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
        let markdown = "![](\(relativePath))"
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
