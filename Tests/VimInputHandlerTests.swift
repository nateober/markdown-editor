import Testing
@testable import MarkdownEditor

@Suite("VimInputHandler")
struct VimInputHandlerTests {

    // MARK: - Initial State

    @Test("Initial mode is normal")
    func initialModeIsNormal() {
        let handler = VimInputHandler()
        #expect(handler.mode == .normal)
    }

    // MARK: - Mode Changes

    @Test("i enters insert mode")
    func iEntersInsertMode() {
        let handler = VimInputHandler()
        let result = handler.handleKey("i")
        #expect(result == .modeChange(.insert))
        #expect(handler.mode == .insert)
    }

    @Test("Escape returns to normal mode from insert")
    func escapeReturnsToNormal() {
        let handler = VimInputHandler()
        _ = handler.handleKey("i")
        let result = handler.handleKey("\u{1B}")
        #expect(result == .modeChange(.normal))
        #expect(handler.mode == .normal)
    }

    @Test("v enters visual mode")
    func vEntersVisualMode() {
        let handler = VimInputHandler()
        let result = handler.handleKey("v")
        #expect(result == .modeChange(.visual))
        #expect(handler.mode == .visual)
    }

    @Test("V enters visual line mode")
    func shiftVEntersVisualLineMode() {
        let handler = VimInputHandler()
        let result = handler.handleKey("V")
        #expect(result == .modeChange(.visualLine))
        #expect(handler.mode == .visualLine)
    }

    @Test("Escape returns to normal from visual mode")
    func escapeFromVisualMode() {
        let handler = VimInputHandler()
        _ = handler.handleKey("v")
        let result = handler.handleKey("\u{1B}")
        #expect(result == .modeChange(.normal))
        #expect(handler.mode == .normal)
    }

    @Test("a enters insert mode after cursor")
    func aInsertsAfterCursor() {
        let handler = VimInputHandler()
        let result = handler.handleKey("a")
        #expect(result == .insertAfterCursor)
        #expect(handler.mode == .insert)
    }

    @Test("A enters insert mode at end of line")
    func shiftAInsertsAtEndOfLine() {
        let handler = VimInputHandler()
        let result = handler.handleKey("A")
        #expect(result == .insertAtEndOfLine)
        #expect(handler.mode == .insert)
    }

    @Test("I enters insert mode at first non-blank")
    func shiftIInsertsAtLineStart() {
        let handler = VimInputHandler()
        let result = handler.handleKey("I")
        #expect(result == .insertAtLineStart)
        #expect(handler.mode == .insert)
    }

    @Test("o opens line below and enters insert mode")
    func oOpensLineBelow() {
        let handler = VimInputHandler()
        let result = handler.handleKey("o")
        #expect(result == .openLineBelow)
        #expect(handler.mode == .insert)
    }

    @Test("O opens line above and enters insert mode")
    func shiftOOpensLineAbove() {
        let handler = VimInputHandler()
        let result = handler.handleKey("O")
        #expect(result == .openLineAbove)
        #expect(handler.mode == .insert)
    }

    // MARK: - Count Prefix

    @Test("Count prefix accumulates")
    func countPrefixAccumulates() {
        let handler = VimInputHandler()
        let r1 = handler.handleKey("3")
        #expect(r1 == .pending)
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 3))
    }

    @Test("Multi-digit count prefix")
    func multiDigitCount() {
        let handler = VimInputHandler()
        _ = handler.handleKey("1")
        _ = handler.handleKey("2")
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 12))
    }

    @Test("Count prefix with zero appended")
    func countPrefixWithZero() {
        let handler = VimInputHandler()
        _ = handler.handleKey("1")
        _ = handler.handleKey("0")
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 10))
    }

    @Test("Zero without prior count is line start motion")
    func zeroAloneIsLineStart() {
        let handler = VimInputHandler()
        let result = handler.handleKey("0")
        #expect(result == .motion(.lineStart, count: 1))
    }

    // MARK: - Motions

    @Test("h moves left")
    func hMovesLeft() {
        let handler = VimInputHandler()
        let result = handler.handleKey("h")
        #expect(result == .motion(.left, count: 1))
    }

    @Test("j moves down")
    func jMovesDown() {
        let handler = VimInputHandler()
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 1))
    }

    @Test("k moves up")
    func kMovesUp() {
        let handler = VimInputHandler()
        let result = handler.handleKey("k")
        #expect(result == .motion(.up, count: 1))
    }

    @Test("l moves right")
    func lMovesRight() {
        let handler = VimInputHandler()
        let result = handler.handleKey("l")
        #expect(result == .motion(.right, count: 1))
    }

    @Test("w moves word forward")
    func wMovesWordForward() {
        let handler = VimInputHandler()
        let result = handler.handleKey("w")
        #expect(result == .motion(.wordForward, count: 1))
    }

    @Test("b moves word backward")
    func bMovesWordBackward() {
        let handler = VimInputHandler()
        let result = handler.handleKey("b")
        #expect(result == .motion(.wordBackward, count: 1))
    }

    @Test("e moves to word end")
    func eMovesToWordEnd() {
        let handler = VimInputHandler()
        let result = handler.handleKey("e")
        #expect(result == .motion(.wordEnd, count: 1))
    }

    @Test("$ moves to line end")
    func dollarMovesToLineEnd() {
        let handler = VimInputHandler()
        let result = handler.handleKey("$")
        #expect(result == .motion(.lineEnd, count: 1))
    }

    @Test("^ moves to first non-blank")
    func caretMovesToFirstNonBlank() {
        let handler = VimInputHandler()
        let result = handler.handleKey("^")
        #expect(result == .motion(.firstNonBlank, count: 1))
    }

    @Test("G moves to document end")
    func shiftGMovesToDocumentEnd() {
        let handler = VimInputHandler()
        let result = handler.handleKey("G")
        #expect(result == .motion(.documentEnd, count: 1))
    }

    @Test("gg moves to document start")
    func ggMovesToDocumentStart() {
        let handler = VimInputHandler()
        let r1 = handler.handleKey("g")
        #expect(r1 == .pending)
        let result = handler.handleKey("g")
        #expect(result == .motion(.documentStart, count: 1))
    }

    @Test("{ moves paragraph up")
    func openBraceMovesUp() {
        let handler = VimInputHandler()
        let result = handler.handleKey("{")
        #expect(result == .motion(.paragraphUp, count: 1))
    }

    @Test("} moves paragraph down")
    func closeBraceMovesDown() {
        let handler = VimInputHandler()
        let result = handler.handleKey("}")
        #expect(result == .motion(.paragraphDown, count: 1))
    }

    @Test("% moves to matching brace")
    func percentMovesToMatchingBrace() {
        let handler = VimInputHandler()
        let result = handler.handleKey("%")
        #expect(result == .motion(.matchingBrace, count: 1))
    }

    @Test("f followed by char is find motion")
    func fFollowedByChar() {
        let handler = VimInputHandler()
        let r1 = handler.handleKey("f")
        #expect(r1 == .pending)
        let result = handler.handleKey("x")
        #expect(result == .motion(.findChar("x"), count: 1))
    }

    @Test("t followed by char is till motion")
    func tFollowedByChar() {
        let handler = VimInputHandler()
        let r1 = handler.handleKey("t")
        #expect(r1 == .pending)
        let result = handler.handleKey("x")
        #expect(result == .motion(.tillChar("x"), count: 1))
    }

    // MARK: - Operators

    @Test("dd produces delete-line")
    func ddDeletesLine() {
        let handler = VimInputHandler()
        let r1 = handler.handleKey("d")
        #expect(r1 == .pending)
        let result = handler.handleKey("d")
        #expect(result == .operatorLine(.delete, count: 1))
    }

    @Test("dw produces delete word")
    func dwDeletesWord() {
        let handler = VimInputHandler()
        _ = handler.handleKey("d")
        let result = handler.handleKey("w")
        #expect(result == .operatorMotion(.delete, .wordForward, count: 1))
    }

    @Test("yy produces yank line")
    func yyYanksLine() {
        let handler = VimInputHandler()
        _ = handler.handleKey("y")
        let result = handler.handleKey("y")
        #expect(result == .operatorLine(.yank, count: 1))
    }

    @Test("cc produces change line")
    func ccChangesLine() {
        let handler = VimInputHandler()
        _ = handler.handleKey("c")
        let result = handler.handleKey("c")
        #expect(result == .operatorLine(.change, count: 1))
    }

    @Test(">> produces indent line")
    func doubleGreaterIndentsLine() {
        let handler = VimInputHandler()
        _ = handler.handleKey(">")
        let result = handler.handleKey(">")
        #expect(result == .operatorLine(.indent, count: 1))
    }

    @Test("<< produces outdent line")
    func doubleLessOutdentsLine() {
        let handler = VimInputHandler()
        _ = handler.handleKey("<")
        let result = handler.handleKey("<")
        #expect(result == .operatorLine(.outdent, count: 1))
    }

    @Test("d$ deletes to end of line")
    func dDollarDeletesToEnd() {
        let handler = VimInputHandler()
        _ = handler.handleKey("d")
        let result = handler.handleKey("$")
        #expect(result == .operatorMotion(.delete, .lineEnd, count: 1))
    }

    @Test("3dd deletes 3 lines")
    func threeDD() {
        let handler = VimInputHandler()
        _ = handler.handleKey("3")
        _ = handler.handleKey("d")
        let result = handler.handleKey("d")
        #expect(result == .operatorLine(.delete, count: 3))
    }

    @Test("d2w deletes 2 words")
    func d2w() {
        let handler = VimInputHandler()
        _ = handler.handleKey("d")
        _ = handler.handleKey("2")
        let result = handler.handleKey("w")
        #expect(result == .operatorMotion(.delete, .wordForward, count: 2))
    }

    @Test("3dw deletes 3 words via count prefix")
    func threeDW() {
        let handler = VimInputHandler()
        _ = handler.handleKey("3")
        _ = handler.handleKey("d")
        let result = handler.handleKey("w")
        #expect(result == .operatorMotion(.delete, .wordForward, count: 3))
    }

    @Test("dgg deletes to document start")
    func dgg() {
        let handler = VimInputHandler()
        _ = handler.handleKey("d")
        _ = handler.handleKey("g")
        let result = handler.handleKey("g")
        #expect(result == .operatorMotion(.delete, .documentStart, count: 1))
    }

    @Test("df followed by char deletes to find")
    func dfChar() {
        let handler = VimInputHandler()
        _ = handler.handleKey("d")
        _ = handler.handleKey("f")
        let result = handler.handleKey("x")
        #expect(result == .operatorMotion(.delete, .findChar("x"), count: 1))
    }

    // MARK: - Single Commands

    @Test("x deletes character")
    func xDeletesChar() {
        let handler = VimInputHandler()
        let result = handler.handleKey("x")
        #expect(result == .deleteChar(count: 1))
    }

    @Test("X deletes character before cursor")
    func shiftXDeletesCharBefore() {
        let handler = VimInputHandler()
        let result = handler.handleKey("X")
        #expect(result == .deleteCharBefore(count: 1))
    }

    @Test("r followed by char replaces character")
    func rReplacesChar() {
        let handler = VimInputHandler()
        _ = handler.handleKey("r")
        let result = handler.handleKey("z")
        #expect(result == .replaceChar("z"))
    }

    @Test("p pastes after cursor")
    func pPastesAfter() {
        let handler = VimInputHandler()
        let result = handler.handleKey("p")
        #expect(result == .pasteAfter)
    }

    @Test("P pastes before cursor")
    func shiftPPastesBefore() {
        let handler = VimInputHandler()
        let result = handler.handleKey("P")
        #expect(result == .pasteBefore)
    }

    @Test("u undoes")
    func uUndoes() {
        let handler = VimInputHandler()
        let result = handler.handleKey("u")
        #expect(result == .undo)
    }

    @Test("Ctrl+R redoes")
    func ctrlRRedoes() {
        let handler = VimInputHandler()
        let result = handler.handleKey("\u{12}", modifiers: .control)
        #expect(result == .redo)
    }

    @Test(". repeats last change")
    func dotRepeats() {
        let handler = VimInputHandler()
        let result = handler.handleKey(".")
        #expect(result == .repeatLastChange)
    }

    @Test("J joins lines")
    func shiftJJoinsLines() {
        let handler = VimInputHandler()
        let result = handler.handleKey("J")
        #expect(result == .joinLines)
    }

    @Test("/ begins search forward")
    func slashSearches() {
        let handler = VimInputHandler()
        let result = handler.handleKey("/")
        #expect(result == .searchForward)
    }

    // MARK: - Insert Mode Passthrough

    @Test("Keys pass through in insert mode")
    func keysPassThroughInInsert() {
        let handler = VimInputHandler()
        _ = handler.handleKey("i")
        let result = handler.handleKey("a")
        #expect(result == .passthrough)
    }

    @Test("All regular keys pass through in insert mode")
    func allRegularKeysPassThrough() {
        let handler = VimInputHandler()
        _ = handler.handleKey("i")
        for char: Character in ["h", "j", "k", "l", "d", "x", "w"] {
            let result = handler.handleKey(char)
            #expect(result == .passthrough)
        }
    }

    // MARK: - Reset

    @Test("Reset returns to normal idle state")
    func resetWorks() {
        let handler = VimInputHandler()
        _ = handler.handleKey("i")
        handler.reset()
        #expect(handler.mode == .normal)
        // Should be back in normal mode, so j should be a motion
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 1))
    }

    // MARK: - Count with operators

    @Test("5x deletes 5 characters")
    func fiveX() {
        let handler = VimInputHandler()
        _ = handler.handleKey("5")
        let result = handler.handleKey("x")
        #expect(result == .deleteChar(count: 5))
    }

    @Test("2j moves down 2")
    func twoJ() {
        let handler = VimInputHandler()
        _ = handler.handleKey("2")
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 2))
    }

    // MARK: - Edge Cases

    @Test("Escape in normal mode stays in normal")
    func escapeInNormalMode() {
        let handler = VimInputHandler()
        let result = handler.handleKey("\u{1B}")
        #expect(result == .modeChange(.normal))
        #expect(handler.mode == .normal)
    }

    @Test("Count prefix reset on mode change")
    func countResetOnModeChange() {
        let handler = VimInputHandler()
        _ = handler.handleKey("3")
        _ = handler.handleKey("i") // enters insert, count consumed
        #expect(handler.mode == .insert)
        _ = handler.handleKey("\u{1B}") // back to normal
        // Count should be reset, j should have count 1
        let result = handler.handleKey("j")
        #expect(result == .motion(.down, count: 1))
    }

    @Test("2fx finds char with count")
    func twoFx() {
        let handler = VimInputHandler()
        _ = handler.handleKey("2")
        _ = handler.handleKey("f")
        let result = handler.handleKey("x")
        #expect(result == .motion(.findChar("x"), count: 2))
    }
}
