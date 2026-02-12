# MarkdownEditor Improvements Design

## Overview

Three areas of improvement: fix broken status bar, complete vim implementation, and improve robustness. All changes stay within existing architecture patterns.

---

## 1. Fix Broken Status Bar

### Problem

`ContentView` declares `@State private var vimMode: VimMode = .normal` and `@State private var cursorPosition: Int = 0` but neither is ever updated. The status bar permanently shows "NORMAL" and "Ln 1, Col 1".

### Design

Add callback closures to `MarkdownTextView` (the NSViewRepresentable bridge):

```
MarkdownTextView(
    text: $document.text,
    fontSize: fontSize,
    vimEnabled: vimModeEnabled,
    onCursorChange: { line, column in ... },
    onVimModeChange: { mode in ... }
)
```

**Cursor position:** Override `setSelectedRange(_:)` in `MarkdownNSTextView` to post cursor changes. The Coordinator in `MarkdownTextView` receives these and fires `onCursorChange`. Use `NSString.lineRange(for:)` to compute line number efficiently — count newlines up to cursor position using `NSString.substring(to:)`.

**Vim mode:** After every `dispatchVimResult()`, check if `vimHandler.mode` changed and notify via the Coordinator. The Coordinator fires `onVimModeChange`.

**ContentView wiring:** Replace dead `@State` vars with callback-driven state. Pass through `EditorContainerView` and `SideBySideView` to reach `MarkdownTextView`.

### Files Changed

- `MarkdownTextView.swift` — add callback parameters, Coordinator propagation
- `MarkdownNSTextView.swift` — override `setSelectedRange`, add mode change notification
- `EditorContainerView.swift` — pass callbacks through
- `SideBySideView.swift` — pass callbacks through
- `ContentView.swift` — wire callbacks to state
- `String+Markdown.swift` — can remove `lineAndColumn(at:)` if unused elsewhere

---

## 2. Vim Completeness

### 2a. Dot Command

**Problem:** `.repeatLastChange` is stubbed out. PRFAQ promises it works.

**Design:** Add recording infrastructure to `VimInputHandler`:

- New `struct LastChange` storing: the `VimResult` that triggered the change, plus any text inserted during insert mode
- `isRecording: Bool` flag — set true when an editing command starts (d, c, x, r, s, o, O, A, I)
- `insertBuffer: String` — accumulates characters typed during insert mode
- When Escape returns to normal mode, finalize the recording: store the trigger result + insertBuffer as `lastChange`
- On `.` key: replay `lastChange` — emit the stored VimResult, then if there's insert text, emit it as a `.replayInsert(String)` result
- Add `.replayInsert(String)` case to `VimResult`
- `MarkdownNSTextView.dispatchVimResult` handles `.replayInsert` by inserting the text and returning to normal mode

**Stays testable:** All recording logic lives in `VimInputHandler` (pure state machine).

### 2b. Text Objects

**Problem:** `iw`, `aw`, `i"`, `a"`, `i(`, `a(`, `i{`, `a{` not implemented.

**Design:**

New enum in `VimMotions.swift`:
```
enum VimTextObject: Equatable, Sendable {
    case innerWord, aroundWord
    case inner(Character), around(Character)  // delimiter-based: ", ', (, {, [
}
```

New `VimResult` case:
```
case operatorTextObject(VimOperator, VimTextObject, Int)
```

`VimInputHandler` changes:
- When in operator-pending state and `i` or `a` is pressed, enter text-object-pending state
- Next key determines the text object (w, ", ', (, ), {, }, [, ])
- Emit `.operatorTextObject`

`VimMotionExecutor` additions:
- `rangeForTextObject(_:on:)` method
- For `innerWord`/`aroundWord`: scan word boundaries using character class (alphanumeric+underscore vs other)
- For delimiter-based: scan outward from cursor for matching pair; `inner` excludes delimiters, `around` includes them
- Handle nested parens/braces with a counter

`MarkdownNSTextView` additions:
- New `executeOperatorTextObject()` method, same pattern as `executeOperatorMotion()`

### 2c. Word-End Motion

**Problem:** `e` motion uses `moveWordForward` which overshoots to start of next word.

**Design:** Add `executeWordEnd()` to `VimMotionExecutor`:
- From cursor, skip whitespace, then advance through word characters (or non-word non-whitespace characters) to find the last character of the word
- Uses `NSString` character scanning, same approach as other motions
- Also add `rangeForWordEnd()` for operator+e combinations

### Files Changed

- `VimInputHandler.swift` — dot command recording, text object state machine branches
- `VimMotions.swift` — `VimTextObject` enum, `VimResult.operatorTextObject`, `VimResult.replayInsert`, word-end range calculation
- `MarkdownNSTextView.swift` — dispatch new result cases, `executeOperatorTextObject()`
- `VimInputHandlerTests.swift` — tests for dot command, text objects

---

## 3. Robustness & Polish

### 3a. Image Path Encoding

**Problem:** `![](\(relativePath))` breaks on spaces and parentheses.

**Fix:** In `MarkdownNSTextView.insertMarkdownImageSyntax()`, percent-encode the path:
```swift
let encoded = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath
let markdown = "![](\(encoded))"
```

### 3b. File Load Error Feedback

**Problem:** `ContentView.openFileInDocument()` silently fails.

**Fix:** Show an alert when loading fails. Extract the error and present via `NSAlert` on the key window, same pattern as `showDocumentNotSavedAlert()` in MarkdownNSTextView.

### 3c. DOCX Export Without Shell Commands

**Problem:** `DOCXExporter` shells out to `/usr/bin/unzip` and `/usr/bin/zip`.

**Fix:** Replace with in-process ZIP handling:
- Use `Foundation`'s `Archive` (available macOS 14+) or write a minimal ZIP builder
- Since DOCX is a known ZIP structure (we create it ourselves), we can build the ZIP archive in-memory using `Data` and the ZIP local file header format
- Alternatively: since we already create the initial DOCX via `NSAttributedString` RTFD conversion, and then modify `document.xml` inside it — we can read the ZIP entries with a simple Swift ZIP reader, modify the XML entry, and write a new ZIP
- Simplest approach: use `Process` only as fallback, prefer `NSData+compression` for the ZIP manipulation

### Files Changed

- `MarkdownNSTextView.swift` — image path encoding (1 line)
- `ContentView.swift` — error alert on file load failure
- `DOCXExporter.swift` — replace Process-based ZIP with Swift ZIP handling

---

## Implementation Order

1. **Status bar fix** — highest impact, unblocks correct UX
2. **Word-end motion** — small, self-contained
3. **Image path encoding** — one-line fix
4. **File load error feedback** — small UX improvement
5. **Dot command** — medium complexity, high value
6. **Text objects** — medium-high complexity, builds on operator infrastructure
7. **DOCX export** — medium complexity, isolated to one file

Steps 1-4 can be done quickly. Steps 5-6 are the bulk of the work. Step 7 is independent.
