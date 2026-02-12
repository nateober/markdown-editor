import AppKit

/// Translates VimMotion enum values into NSTextView cursor operations.
/// Operates on a given NSTextView to perform cursor movement and text manipulation.
final class VimMotionExecutor {

    // MARK: - Motion Execution

    /// Execute a motion on the given text view.
    /// - Parameters:
    ///   - motion: The Vim motion to execute.
    ///   - textView: The NSTextView to operate on.
    ///   - count: Number of times to repeat the motion.
    ///   - extending: If true, extend the selection (for visual mode).
    func executeMotion(_ motion: VimMotion, on textView: NSTextView, count: Int = 1, extending: Bool = false) {
        for _ in 0..<count {
            executeSingleMotion(motion, on: textView, extending: extending)
        }
    }

    /// Get the range that a motion would cover from the current cursor position.
    /// Used by operators (delete, change, yank) to determine the affected range.
    /// - Parameters:
    ///   - motion: The Vim motion.
    ///   - textView: The NSTextView to query.
    ///   - count: Number of times to repeat.
    /// - Returns: The NSRange that the motion covers.
    func rangeForMotion(_ motion: VimMotion, on textView: NSTextView, count: Int = 1) -> NSRange {
        let startLocation = textView.selectedRange().location
        // Save state
        let savedRange = textView.selectedRange()

        // Execute the motion to find where it ends
        executeMotion(motion, on: textView, count: count, extending: false)
        let endLocation = textView.selectedRange().location

        // Restore cursor
        textView.setSelectedRange(savedRange)

        let maxLen = (textView.string as NSString).length
        let loc = min(startLocation, endLocation)
        let len = min(abs(endLocation - startLocation), maxLen - loc)
        return NSRange(location: loc, length: len)
    }

    /// Get the range for an entire line (or multiple lines) at the current cursor.
    /// - Parameters:
    ///   - textView: The NSTextView.
    ///   - count: Number of lines to include.
    /// - Returns: The NSRange covering the line(s).
    func rangeForLines(on textView: NSTextView, count: Int = 1) -> NSRange {
        let string = textView.string as NSString
        let cursorLocation = textView.selectedRange().location

        guard string.length > 0 else {
            return NSRange(location: 0, length: 0)
        }

        // Find start of current line
        let lineRange = string.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let startOfLine = lineRange.location

        // Extend to cover `count` lines
        var endOfLine = NSMaxRange(lineRange)
        for _ in 1..<count {
            if endOfLine < string.length {
                let nextLineRange = string.lineRange(for: NSRange(location: endOfLine, length: 0))
                endOfLine = NSMaxRange(nextLineRange)
            }
        }

        return NSRange(location: startOfLine, length: endOfLine - startOfLine)
    }

    // MARK: - Single Motion Dispatch

    private func executeSingleMotion(_ motion: VimMotion, on textView: NSTextView, extending: Bool) {
        switch motion {
        case .left:
            if extending {
                textView.moveBackwardAndModifySelection(nil)
            } else {
                textView.moveBackward(nil)
            }

        case .right:
            if extending {
                textView.moveForwardAndModifySelection(nil)
            } else {
                textView.moveForward(nil)
            }

        case .up:
            if extending {
                textView.moveUpAndModifySelection(nil)
            } else {
                textView.moveUp(nil)
            }

        case .down:
            if extending {
                textView.moveDownAndModifySelection(nil)
            } else {
                textView.moveDown(nil)
            }

        case .wordForward:
            if extending {
                textView.moveWordForwardAndModifySelection(nil)
            } else {
                textView.moveWordForward(nil)
            }

        case .wordBackward:
            if extending {
                textView.moveWordBackwardAndModifySelection(nil)
            } else {
                textView.moveWordBackward(nil)
            }

        case .wordEnd:
            moveToWordEnd(on: textView, extending: extending)

        case .lineStart:
            if extending {
                textView.moveToBeginningOfLineAndModifySelection(nil)
            } else {
                textView.moveToBeginningOfLine(nil)
            }

        case .lineEnd:
            if extending {
                textView.moveToEndOfLineAndModifySelection(nil)
            } else {
                textView.moveToEndOfLine(nil)
            }

        case .firstNonBlank:
            // Move to beginning of line, then skip whitespace
            if extending {
                textView.moveToBeginningOfLineAndModifySelection(nil)
            } else {
                textView.moveToBeginningOfLine(nil)
            }
            skipWhitespace(on: textView, extending: extending)

        case .documentStart:
            if extending {
                textView.moveToBeginningOfDocumentAndModifySelection(nil)
            } else {
                textView.moveToBeginningOfDocument(nil)
            }

        case .documentEnd:
            if extending {
                textView.moveToEndOfDocumentAndModifySelection(nil)
            } else {
                textView.moveToEndOfDocument(nil)
            }

        case .paragraphUp:
            if extending {
                textView.moveParagraphBackwardAndModifySelection(nil)
            } else {
                moveParagraphBackward(on: textView)
            }

        case .paragraphDown:
            if extending {
                textView.moveParagraphForwardAndModifySelection(nil)
            } else {
                moveParagraphForward(on: textView)
            }

        case .matchingBrace:
            moveToMatchingBrace(on: textView, extending: extending)

        case .findChar(let ch):
            moveToChar(ch, on: textView, extending: extending, before: false)

        case .tillChar(let ch):
            moveToChar(ch, on: textView, extending: extending, before: true)
        }
    }

    // MARK: - Custom Motion Helpers

    private func skipWhitespace(on textView: NSTextView, extending: Bool) {
        let string = textView.string as NSString
        var location = textView.selectedRange().location
        while location < string.length {
            let ch = string.character(at: location)
            if ch == 0x20 || ch == 0x09 { // space or tab
                if extending {
                    textView.moveForwardAndModifySelection(nil)
                } else {
                    textView.moveForward(nil)
                }
                location += 1
            } else {
                break
            }
        }
    }

    private func moveToWordEnd(on textView: NSTextView, extending: Bool) {
        let string = textView.string as NSString
        var pos = textView.selectedRange().location

        guard pos < string.length else { return }

        // Move past current character first (vim 'e' from current position)
        pos += 1

        // Skip whitespace
        while pos < string.length {
            let ch = string.character(at: pos)
            if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                pos += 1
            } else {
                break
            }
        }

        guard pos < string.length else {
            // At end of document
            let target = string.length > 0 ? string.length - 1 : 0
            if extending {
                let currentRange = textView.selectedRange()
                let newLen = target - currentRange.location + 1
                textView.setSelectedRange(NSRange(location: currentRange.location, length: max(0, newLen)))
            } else {
                textView.setSelectedRange(NSRange(location: target, length: 0))
            }
            return
        }

        // Determine character class at current position
        let startChar = string.character(at: pos)
        let isWord = isWordChar(startChar)

        // Advance through same character class
        while pos + 1 < string.length {
            let nextChar = string.character(at: pos + 1)
            let nextIsWhitespace = nextChar == 0x20 || nextChar == 0x09 || nextChar == 0x0A || nextChar == 0x0D
            if nextIsWhitespace { break }
            let nextIsWord = isWordChar(nextChar)
            if nextIsWord != isWord { break }
            pos += 1
        }

        // pos is now on the last character of the word
        if extending {
            let currentRange = textView.selectedRange()
            let newLen = pos - currentRange.location + 1
            textView.setSelectedRange(NSRange(location: currentRange.location, length: max(0, newLen)))
        } else {
            textView.setSelectedRange(NSRange(location: pos, length: 0))
        }
    }

    private func isWordChar(_ ch: unichar) -> Bool {
        // Word characters: alphanumeric and underscore
        if ch >= 0x30 && ch <= 0x39 { return true }  // 0-9
        if ch >= 0x41 && ch <= 0x5A { return true }  // A-Z
        if ch >= 0x61 && ch <= 0x7A { return true }  // a-z
        if ch == 0x5F { return true }                 // _
        return false
    }

    private func moveParagraphBackward(on textView: NSTextView) {
        let string = textView.string as NSString
        var location = textView.selectedRange().location

        // Skip current blank lines
        while location > 0 {
            let prevLine = string.lineRange(for: NSRange(location: location - 1, length: 0))
            let lineContent = string.substring(with: prevLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if lineContent.isEmpty {
                location = prevLine.location
            } else {
                break
            }
        }

        // Now skip non-blank lines
        while location > 0 {
            let prevLine = string.lineRange(for: NSRange(location: location - 1, length: 0))
            let lineContent = string.substring(with: prevLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if !lineContent.isEmpty {
                location = prevLine.location
            } else {
                break
            }
        }

        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    private func moveParagraphForward(on textView: NSTextView) {
        let string = textView.string as NSString
        var location = textView.selectedRange().location

        // Skip current non-blank lines
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let lineContent = string.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !lineContent.isEmpty {
                location = NSMaxRange(lineRange)
            } else {
                break
            }
        }

        // Skip blank lines
        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let lineContent = string.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if lineContent.isEmpty {
                location = NSMaxRange(lineRange)
            } else {
                break
            }
        }

        textView.setSelectedRange(NSRange(location: location, length: 0))
    }

    private func moveToMatchingBrace(on textView: NSTextView, extending: Bool) {
        let string = textView.string as NSString
        let location = textView.selectedRange().location

        guard location < string.length else { return }
        guard let scalar = UnicodeScalar(string.character(at: location)) else { return }

        let ch = Character(scalar)
        let pairs: [(Character, Character)] = [
            ("(", ")"), ("[", "]"), ("{", "}")
        ]

        for (open, close) in pairs {
            if ch == open {
                // Search forward for matching close
                if let matchPos = findMatchingForward(open: open, close: close, in: string, from: location) {
                    let target = NSRange(location: matchPos, length: 0)
                    if extending {
                        let currentRange = textView.selectedRange()
                        let newLen = matchPos - currentRange.location + 1
                        textView.setSelectedRange(NSRange(location: currentRange.location, length: newLen))
                    } else {
                        textView.setSelectedRange(target)
                    }
                }
                return
            } else if ch == close {
                // Search backward for matching open
                if let matchPos = findMatchingBackward(open: open, close: close, in: string, from: location) {
                    let target = NSRange(location: matchPos, length: 0)
                    if extending {
                        let currentRange = textView.selectedRange()
                        let newStart = matchPos
                        let newLen = NSMaxRange(currentRange) - newStart
                        textView.setSelectedRange(NSRange(location: newStart, length: newLen))
                    } else {
                        textView.setSelectedRange(target)
                    }
                }
                return
            }
        }
    }

    private func findMatchingForward(open: Character, close: Character, in string: NSString, from start: Int) -> Int? {
        var depth = 0
        for i in start..<string.length {
            guard let scalar = UnicodeScalar(string.character(at: i)) else { continue }
            let ch = Character(scalar)
            if ch == open { depth += 1 }
            else if ch == close { depth -= 1 }
            if depth == 0 { return i }
        }
        return nil
    }

    private func findMatchingBackward(open: Character, close: Character, in string: NSString, from start: Int) -> Int? {
        var depth = 0
        for i in stride(from: start, through: 0, by: -1) {
            guard let scalar = UnicodeScalar(string.character(at: i)) else { continue }
            let ch = Character(scalar)
            if ch == close { depth += 1 }
            else if ch == open { depth -= 1 }
            if depth == 0 { return i }
        }
        return nil
    }

    private func moveToChar(_ target: Character, on textView: NSTextView, extending: Bool, before: Bool) {
        let string = textView.string as NSString
        let startLocation = textView.selectedRange().location + 1

        guard startLocation < string.length else { return }

        guard let targetScalar = target.unicodeScalars.first else { return }
        for i in startLocation..<string.length {
            let ch = string.character(at: i)
            if ch == targetScalar.value {
                let destination = before ? i - 1 : i
                guard destination >= 0 else { return }
                if extending {
                    let currentRange = textView.selectedRange()
                    let newLen = destination - currentRange.location + 1
                    textView.setSelectedRange(NSRange(location: currentRange.location, length: max(0, newLen)))
                } else {
                    textView.setSelectedRange(NSRange(location: destination, length: 0))
                }
                return
            }
        }
    }
}
