import AppKit

class MarkdownNSTextView: NSTextView {

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
}
