import Foundation

// MARK: - VimMotion

/// Describes a cursor motion in Vim.
enum VimMotion: Equatable, Sendable {
    case left
    case down
    case up
    case right
    case wordForward
    case wordBackward
    case wordEnd
    case lineStart       // 0
    case lineEnd         // $
    case firstNonBlank   // ^
    case documentEnd     // G
    case documentStart   // gg
    case paragraphUp     // {
    case paragraphDown   // }
    case matchingBrace   // %
    case findChar(Character)   // f{char}
    case tillChar(Character)   // t{char}
}

// MARK: - VimOperator

/// An operator that acts on a motion range.
enum VimOperator: Equatable, Sendable {
    case delete
    case change
    case yank
    case indent
    case outdent
}

// MARK: - VimResult

/// Describes what the editor should do in response to a key input.
enum VimResult: Equatable, Sendable {
    /// No action needed yet (key was consumed, awaiting more input).
    case pending

    /// Key was not handled by vim; pass through to the text view.
    case passthrough

    /// Change to a new vim mode.
    case modeChange(VimMode)

    /// Execute a cursor motion with optional count.
    case motion(VimMotion, count: Int)

    /// Execute an operator over a motion range.
    case operatorMotion(VimOperator, VimMotion, count: Int)

    /// Execute an operator on the current line (dd, yy, cc, >>, <<).
    case operatorLine(VimOperator, count: Int)

    /// Delete character under cursor (x).
    case deleteChar(count: Int)

    /// Delete character before cursor (X).
    case deleteCharBefore(count: Int)

    /// Replace character under cursor with given character (r{char}).
    case replaceChar(Character)

    /// Paste after cursor.
    case pasteAfter

    /// Paste before cursor.
    case pasteBefore

    /// Undo.
    case undo

    /// Redo.
    case redo

    /// Repeat last change.
    case repeatLastChange

    /// Join current line with next line.
    case joinLines

    /// Open new line below and enter insert mode.
    case openLineBelow

    /// Open new line above and enter insert mode.
    case openLineAbove

    /// Enter insert mode at end of line (A).
    case insertAtEndOfLine

    /// Enter insert mode at first non-blank of line (I).
    case insertAtLineStart

    /// Enter insert mode after cursor (a).
    case insertAfterCursor

    /// Begin forward search.
    case searchForward
}

// MARK: - VimInputHandler

/// A pure state machine that processes key inputs and returns VimResult values.
/// This class has no dependency on AppKit/NSTextView and is fully testable in isolation.
final class VimInputHandler {

    // MARK: - Internal State

    private enum InputState: Equatable, Sendable {
        case idle
        case awaitingMotion(VimOperator)
        case awaitingChar(AwaitingCharReason)
        case awaitingSecondKey(SecondKeyContext)
    }

    private enum AwaitingCharReason: Equatable, Sendable {
        case find        // f
        case till        // t
        case replace     // r
    }

    private enum SecondKeyContext: Equatable, Sendable {
        case g           // g pressed, awaiting second key (gg, etc.)
    }

    private var _mode: VimMode = .normal
    private var _state: InputState = .idle
    private var _countAccumulator: Int = 0
    private var _pendingOperator: VimOperator? = nil

    // MARK: - Public API

    /// The current Vim mode.
    var mode: VimMode { _mode }

    /// Process a key event and return a VimResult.
    /// - Parameters:
    ///   - key: The character pressed.
    ///   - modifiers: Modifier flags (shift, control, etc.)
    /// - Returns: A VimResult describing what the editor should do.
    func handleKey(_ key: Character, modifiers: VimKeyModifiers = []) -> VimResult {
        switch _mode {
        case .insert:
            return handleInsertMode(key, modifiers: modifiers)
        case .normal:
            return handleNormalMode(key, modifiers: modifiers)
        case .visual, .visualLine:
            return handleVisualMode(key, modifiers: modifiers)
        }
    }

    /// Reset the handler to its initial state.
    func reset() {
        _mode = .normal
        _state = .idle
        _countAccumulator = 0
        _pendingOperator = nil
    }

    // MARK: - Insert Mode

    private func handleInsertMode(_ key: Character, modifiers: VimKeyModifiers) -> VimResult {
        if key == "\u{1B}" { // Escape
            _mode = .normal
            _state = .idle
            _countAccumulator = 0
            _pendingOperator = nil
            return .modeChange(.normal)
        }
        // All other keys pass through in insert mode
        return .passthrough
    }

    // MARK: - Visual Mode

    private func handleVisualMode(_ key: Character, modifiers: VimKeyModifiers) -> VimResult {
        if key == "\u{1B}" { // Escape
            _mode = .normal
            _state = .idle
            _countAccumulator = 0
            return .modeChange(.normal)
        }

        // Motions work in visual mode
        if let motion = motionForKey(key) {
            let count = consumeCount()
            return .motion(motion, count: count)
        }

        // Operators in visual mode operate on the selection
        switch key {
        case "d", "x":
            _mode = .normal
            return .operatorMotion(.delete, .right, count: 1)
        case "y":
            _mode = .normal
            return .operatorMotion(.yank, .right, count: 1)
        case "c":
            _mode = .insert
            return .operatorMotion(.change, .right, count: 1)
        default:
            return .pending
        }
    }

    // MARK: - Normal Mode

    private func handleNormalMode(_ key: Character, modifiers: VimKeyModifiers) -> VimResult {
        // Handle states first
        switch _state {
        case .awaitingChar(let reason):
            _state = .idle
            switch reason {
            case .find:
                let count = consumeCount()
                if let op = _pendingOperator {
                    _pendingOperator = nil
                    return .operatorMotion(op, .findChar(key), count: count)
                }
                return .motion(.findChar(key), count: count)
            case .till:
                let count = consumeCount()
                if let op = _pendingOperator {
                    _pendingOperator = nil
                    return .operatorMotion(op, .tillChar(key), count: count)
                }
                return .motion(.tillChar(key), count: count)
            case .replace:
                _ = consumeCount()
                return .replaceChar(key)
            }

        case .awaitingSecondKey(let context):
            _state = .idle
            switch context {
            case .g:
                if key == "g" {
                    let count = consumeCount()
                    if let op = _pendingOperator {
                        _pendingOperator = nil
                        return .operatorMotion(op, .documentStart, count: count)
                    }
                    return .motion(.documentStart, count: count)
                }
                // Unknown g-command, reset
                _ = consumeCount()
                return .pending
            }

        case .awaitingMotion(let op):
            // Check for doubled operator (dd, yy, cc, >>, <<)
            let opChar = charForOperator(op)
            if key == opChar {
                _state = .idle
                _pendingOperator = nil
                let count = consumeCount()
                return .operatorLine(op, count: count)
            }

            // Check for motion after operator
            if key == "g" {
                _state = .awaitingSecondKey(.g)
                return .pending
            }
            if key == "f" {
                _state = .awaitingChar(.find)
                return .pending
            }
            if key == "t" {
                _state = .awaitingChar(.till)
                return .pending
            }

            // Count within operator (e.g., d2w)
            if key.isNumber && key != "0" {
                let digit = Int(String(key))!
                _countAccumulator = _countAccumulator * 10 + digit
                return .pending
            }
            if key == "0" && _countAccumulator > 0 {
                _countAccumulator = _countAccumulator * 10
                return .pending
            }

            if let motion = motionForKey(key) {
                _state = .idle
                _pendingOperator = nil
                let count = consumeCount()
                return .operatorMotion(op, motion, count: count)
            }

            // Unknown motion; reset
            _state = .idle
            _pendingOperator = nil
            _ = consumeCount()
            return .pending

        case .idle:
            break
        }

        // Count prefix accumulation
        if key.isNumber && key != "0" && _pendingOperator == nil {
            let digit = Int(String(key))!
            _countAccumulator = _countAccumulator * 10 + digit
            return .pending
        }
        if key == "0" && _countAccumulator > 0 && _pendingOperator == nil {
            _countAccumulator = _countAccumulator * 10
            return .pending
        }

        // Mode changes
        switch key {
        case "i":
            _mode = .insert
            _ = consumeCount()
            return .modeChange(.insert)
        case "a":
            _mode = .insert
            _ = consumeCount()
            return .insertAfterCursor
        case "A":
            _mode = .insert
            _ = consumeCount()
            return .insertAtEndOfLine
        case "I":
            _mode = .insert
            _ = consumeCount()
            return .insertAtLineStart
        case "o":
            _mode = .insert
            _ = consumeCount()
            return .openLineBelow
        case "O":
            _mode = .insert
            _ = consumeCount()
            return .openLineAbove
        case "v":
            _mode = .visual
            _ = consumeCount()
            return .modeChange(.visual)
        case "V":
            _mode = .visualLine
            _ = consumeCount()
            return .modeChange(.visualLine)
        case "\u{1B}": // Escape in normal mode
            _state = .idle
            _countAccumulator = 0
            _pendingOperator = nil
            return .modeChange(.normal)
        default:
            break
        }

        // Operators
        switch key {
        case "d":
            _pendingOperator = .delete
            _state = .awaitingMotion(.delete)
            return .pending
        case "c":
            _pendingOperator = .change
            _state = .awaitingMotion(.change)
            return .pending
        case "y":
            _pendingOperator = .yank
            _state = .awaitingMotion(.yank)
            return .pending
        case ">":
            _pendingOperator = .indent
            _state = .awaitingMotion(.indent)
            return .pending
        case "<":
            _pendingOperator = .outdent
            _state = .awaitingMotion(.outdent)
            return .pending
        default:
            break
        }

        // g prefix
        if key == "g" {
            _state = .awaitingSecondKey(.g)
            return .pending
        }

        // f, t prefix
        if key == "f" {
            _state = .awaitingChar(.find)
            return .pending
        }
        if key == "t" {
            // Note: "t" is also recognized as a motion key (tillChar) but only when awaiting a char.
            // In idle normal mode, "t" enters awaitingChar for till.
            _state = .awaitingChar(.till)
            return .pending
        }

        // Ctrl+R for redo (must check before "r" for replace)
        if modifiers.contains(.control) && (key == "r" || key == "R" || key == "\u{12}") {
            _ = consumeCount()
            return .redo
        }

        // r prefix
        if key == "r" {
            _state = .awaitingChar(.replace)
            return .pending
        }

        // Simple motions
        if let motion = motionForKey(key) {
            let count = consumeCount()
            return .motion(motion, count: count)
        }

        // Single commands
        switch key {
        case "x":
            let count = consumeCount()
            return .deleteChar(count: count)
        case "X":
            let count = consumeCount()
            return .deleteCharBefore(count: count)
        case "p":
            _ = consumeCount()
            return .pasteAfter
        case "P":
            _ = consumeCount()
            return .pasteBefore
        case "u":
            _ = consumeCount()
            return .undo
        case "J":
            _ = consumeCount()
            return .joinLines
        case ".":
            _ = consumeCount()
            return .repeatLastChange
        case "/":
            _ = consumeCount()
            return .searchForward
        default:
            break
        }

        // Not handled
        return .pending
    }

    // MARK: - Helpers

    private func motionForKey(_ key: Character) -> VimMotion? {
        switch key {
        case "h": return .left
        case "j": return .down
        case "k": return .up
        case "l": return .right
        case "w": return .wordForward
        case "b": return .wordBackward
        case "e": return .wordEnd
        case "0": return .lineStart
        case "$": return .lineEnd
        case "^": return .firstNonBlank
        case "G": return .documentEnd
        case "{": return .paragraphUp
        case "}": return .paragraphDown
        case "%": return .matchingBrace
        default: return nil
        }
    }

    private func charForOperator(_ op: VimOperator) -> Character {
        switch op {
        case .delete: return "d"
        case .change: return "c"
        case .yank: return "y"
        case .indent: return ">"
        case .outdent: return "<"
        }
    }

    private func consumeCount() -> Int {
        let count = _countAccumulator > 0 ? _countAccumulator : 1
        _countAccumulator = 0
        return count
    }
}

// MARK: - VimKeyModifiers

/// Simplified key modifier flags for vim input handling.
struct VimKeyModifiers: OptionSet, Sendable {
    let rawValue: UInt

    static let control = VimKeyModifiers(rawValue: 1 << 0)
    static let shift   = VimKeyModifiers(rawValue: 1 << 1)
    static let option  = VimKeyModifiers(rawValue: 1 << 2)
    static let command = VimKeyModifiers(rawValue: 1 << 3)
}
