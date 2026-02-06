# MarkdownEditor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Mac-native markdown editor with live preview, vim keybindings, and export to PDF/HTML/Word.

**Architecture:** SwiftUI app shell with AppKit NSTextView (via NSViewRepresentable) for editing and WKWebView for preview. ReferenceFileDocument-based document model. MVVM with service layer. cmark-gfm for markdown parsing, regex-based syntax highlighting, state-machine vim keybindings.

**Tech Stack:** Swift, SwiftUI, AppKit (NSTextView), WebKit (WKWebView), cmark-gfm (C interop via libcmark_gfm SPM package), Yams (YAML parsing), DocX (Word export), bundled KaTeX/Mermaid.js/highlight.js for preview rendering.

---

## Phase 1: Foundation

**Goal:** A working document-based app that opens, edits, and saves `.md` files with a basic NSTextView editor.

### Task 1: Initialize Project

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`

**Step 1: Initialize git repo**

Run: `cd /Users/nateober/markdown_editor && git init`

**Step 2: Create .gitignore**

```
.DS_Store
.build/
.swiftpm/
*.xcodeproj/
*.xcworkspace/
xcuserdata/
DerivedData/
*.app
```

**Step 3: Create Package.swift**

```swift
// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/KristopherGBaker/libcmark_gfm.git", from: "0.29.4"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: [
                .product(name: "libcmark_gfm", package: "libcmark_gfm"),
                "Yams",
            ],
            path: "MarkdownEditor"
        ),
        .testTarget(
            name: "MarkdownEditorTests",
            dependencies: ["MarkdownEditor"],
            path: "Tests"
        ),
    ]
)
```

**Step 4: Create directory structure**

Run:
```bash
mkdir -p MarkdownEditor/App
mkdir -p MarkdownEditor/Model
mkdir -p MarkdownEditor/Views/EditorArea
mkdir -p MarkdownEditor/Views/Editor
mkdir -p MarkdownEditor/Views/Preview
mkdir -p MarkdownEditor/Views/Sidebar
mkdir -p MarkdownEditor/Views/StatusBar
mkdir -p MarkdownEditor/Services
mkdir -p MarkdownEditor/Resources
mkdir -p MarkdownEditor/Extensions
mkdir -p Tests
```

**Step 5: Commit**

```bash
git add Package.swift .gitignore
git commit -m "chore: initialize Swift package with dependencies"
```

---

### Task 2: UTType Declaration

**Files:**
- Create: `MarkdownEditor/Extensions/UTType+Markdown.swift`
- Test: `Tests/UTTypeMarkdownTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
import UniformTypeIdentifiers
@testable import MarkdownEditor

@Suite("UTType+Markdown")
struct UTTypeMarkdownTests {
    @Test("Markdown UTType has correct identifier")
    func markdownIdentifier() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
    }

    @Test("Markdown UTType conforms to plainText")
    func conformsToPlainText() {
        #expect(UTType.markdown.conforms(to: .plainText))
    }

    @Test("md extension resolves to markdown type")
    func mdExtension() {
        let type = UTType(filenameExtension: "md")
        #expect(type != nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/nateober/markdown_editor && swift test --filter UTTypeMarkdownTests 2>&1 | tail -20`
Expected: FAIL (module MarkdownEditor doesn't exist yet)

**Step 3: Write implementation**

```swift
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType("net.daringfireball.markdown") ?? UTType(
        exportedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}
```

**Step 4: Create placeholder app entry point** (needed for module to compile)

Create `MarkdownEditor/App/MarkdownEditorApp.swift`:
```swift
import SwiftUI

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        WindowGroup {
            Text("MarkdownEditor")
        }
    }
}
```

**Step 5: Run test to verify it passes**

Run: `cd /Users/nateober/markdown_editor && swift test --filter UTTypeMarkdownTests 2>&1 | tail -20`
Expected: PASS

**Step 6: Commit**

```bash
git add MarkdownEditor/Extensions/UTType+Markdown.swift Tests/UTTypeMarkdownTests.swift MarkdownEditor/App/MarkdownEditorApp.swift
git commit -m "feat: add UTType declaration for markdown files"
```

---

### Task 3: MarkdownDocument Model

**Files:**
- Create: `MarkdownEditor/Model/MarkdownDocument.swift`
- Test: `Tests/MarkdownDocumentTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
import UniformTypeIdentifiers
@testable import MarkdownEditor

@Suite("MarkdownDocument")
struct MarkdownDocumentTests {
    @Test("New document has empty text")
    func newDocumentIsEmpty() {
        let doc = MarkdownDocument()
        #expect(doc.text == "")
    }

    @Test("Document reads from file data")
    func readFromData() throws {
        let markdown = "# Hello\n\nThis is a test."
        let data = Data(markdown.utf8)
        let doc = try MarkdownDocument(data: data)
        #expect(doc.text == markdown)
    }

    @Test("Document writes to data")
    func writeToData() throws {
        let doc = MarkdownDocument()
        doc.text = "# Test\n\nSome content."
        let data = try doc.dataForSaving()
        let result = String(data: data, encoding: .utf8)
        #expect(result == "# Test\n\nSome content.")
    }

    @Test("Document readable content types includes markdown")
    func readableContentTypes() {
        #expect(MarkdownDocument.readableContentTypes.contains(.markdown))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/nateober/markdown_editor && swift test --filter MarkdownDocumentTests 2>&1 | tail -20`
Expected: FAIL (MarkdownDocument not defined)

**Step 3: Write implementation**

```swift
import SwiftUI
import UniformTypeIdentifiers

final class MarkdownDocument: ReferenceFileDocument {
    @Published var text: String

    static var readableContentTypes: [UTType] { [.markdown] }
    static var writableContentTypes: [UTType] { [.markdown] }

    init() {
        self.text = ""
    }

    convenience init(data: Data) throws {
        self.init()
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func snapshot(contentType: UTType) throws -> Data {
        try dataForSaving()
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }

    func dataForSaving() throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/nateober/markdown_editor && swift test --filter MarkdownDocumentTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add MarkdownEditor/Model/MarkdownDocument.swift Tests/MarkdownDocumentTests.swift
git commit -m "feat: add MarkdownDocument with ReferenceFileDocument conformance"
```

---

### Task 4: Basic NSTextView Editor

**Files:**
- Create: `MarkdownEditor/Views/Editor/MarkdownNSTextView.swift`
- Create: `MarkdownEditor/Views/Editor/MarkdownTextView.swift`

**Step 1: Create NSTextView subclass**

```swift
import AppKit

class MarkdownNSTextView: NSTextView {

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
}
```

**Step 2: Create NSViewRepresentable wrapper**

```swift
import SwiftUI
import AppKit

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = MarkdownNSTextView()
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownNSTextView else { return }
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
```

**Step 3: Verify build**

Run: `cd /Users/nateober/markdown_editor && swift build 2>&1 | tail -20`
Expected: Build succeeded

**Step 4: Commit**

```bash
git add MarkdownEditor/Views/Editor/MarkdownNSTextView.swift MarkdownEditor/Views/Editor/MarkdownTextView.swift
git commit -m "feat: add NSTextView-based markdown editor view"
```

---

### Task 5: ContentView and App Entry Point

**Files:**
- Create: `MarkdownEditor/Views/ContentView.swift`
- Modify: `MarkdownEditor/App/MarkdownEditorApp.swift`

**Step 1: Create ContentView**

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument

    var body: some View {
        MarkdownTextView(text: $document.text)
            .frame(minWidth: 600, minHeight: 400)
    }
}
```

**Step 2: Update MarkdownEditorApp to use DocumentGroup**

```swift
import SwiftUI
import UniformTypeIdentifiers

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
```

**Step 3: Verify build**

Run: `cd /Users/nateober/markdown_editor && swift build 2>&1 | tail -20`
Expected: Build succeeded

**Step 4: Test manually** (optional, requires Xcode)

Run: `cd /Users/nateober/markdown_editor && open Package.swift`
Then in Xcode: Product > Run. Verify:
- App launches with a new untitled document
- Can type markdown text in the editor
- Can save (Cmd+S) as a `.md` file
- Can open (Cmd+O) an existing `.md` file

**Step 5: Commit**

```bash
git add MarkdownEditor/Views/ContentView.swift MarkdownEditor/App/MarkdownEditorApp.swift
git commit -m "feat: wire up DocumentGroup with ContentView for document-based editing"
```

---

### Task 6: String+Markdown Extensions

**Files:**
- Create: `MarkdownEditor/Extensions/String+Markdown.swift`
- Test: `Tests/StringMarkdownTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import MarkdownEditor

@Suite("String+Markdown")
struct StringMarkdownTests {
    @Test("Word count for simple text")
    func wordCount() {
        #expect("Hello world".wordCount == 2)
    }

    @Test("Word count for empty string")
    func wordCountEmpty() {
        #expect("".wordCount == 0)
    }

    @Test("Word count ignores extra whitespace")
    func wordCountWhitespace() {
        #expect("  hello   world  ".wordCount == 2)
    }

    @Test("Character count")
    func characterCount() {
        #expect("Hello".characterCount == 5)
    }

    @Test("Reading time for short text")
    func readingTimeShort() {
        let text = Array(repeating: "word", count: 200).joined(separator: " ")
        #expect(text.readingTimeMinutes == 1)
    }

    @Test("Reading time for longer text")
    func readingTimeLonger() {
        let text = Array(repeating: "word", count: 600).joined(separator: " ")
        #expect(text.readingTimeMinutes == 3)
    }

    @Test("Reading time for empty text is zero")
    func readingTimeEmpty() {
        #expect("".readingTimeMinutes == 0)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/nateober/markdown_editor && swift test --filter StringMarkdownTests 2>&1 | tail -20`
Expected: FAIL

**Step 3: Write implementation**

```swift
import Foundation

extension String {
    var wordCount: Int {
        self.split { $0.isWhitespace || $0.isNewline }.count
    }

    var characterCount: Int {
        self.count
    }

    var readingTimeMinutes: Int {
        max(0, Int((Double(wordCount) / 200.0).rounded(.up)))
    }

    func lineAndColumn(at offset: Int) -> (line: Int, column: Int) {
        let target = self.index(startIndex, offsetBy: min(offset, count))
        var line = 1
        var column = 1
        for idx in self.indices {
            if idx == target { break }
            if self[idx] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return (line, column)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/nateober/markdown_editor && swift test --filter StringMarkdownTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add MarkdownEditor/Extensions/String+Markdown.swift Tests/StringMarkdownTests.swift
git commit -m "feat: add String extensions for word count, char count, reading time"
```

---

### Task 7: Phase 1 Verification

**Step 1: Run full test suite**

Run: `cd /Users/nateober/markdown_editor && swift test 2>&1 | tail -30`
Expected: All tests pass

**Step 2: Run full build**

Run: `cd /Users/nateober/markdown_editor && swift build 2>&1 | tail -10`
Expected: Build succeeded

**Step 3: Tag**

```bash
git add -A && git status
git commit -m "chore: phase 1 complete - document-based editor foundation"
git tag v0.1.0-phase1
```

---

## Phase 2: Live Preview

**Goal:** Side-by-side editing with real-time HTML preview rendered in WKWebView.

### Task 8: MarkdownParser Service

**Files:**
- Create: `MarkdownEditor/Services/MarkdownParser.swift`
- Test: `Tests/MarkdownParserTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import MarkdownEditor

@Suite("MarkdownParser")
struct MarkdownParserTests {
    let parser = MarkdownParser()

    @Test("Parse heading to HTML")
    func parseHeading() {
        let result = parser.parse("# Hello")
        #expect(result.contains("<h1>"))
        #expect(result.contains("Hello"))
    }

    @Test("Parse bold text")
    func parseBold() {
        let result = parser.parse("**bold**")
        #expect(result.contains("<strong>bold</strong>"))
    }

    @Test("Parse GFM table")
    func parseTable() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let result = parser.parse(md)
        #expect(result.contains("<table>"))
    }

    @Test("Parse GFM task list")
    func parseTaskList() {
        let md = "- [x] Done\n- [ ] Todo"
        let result = parser.parse(md)
        #expect(result.contains("checked"))
    }

    @Test("Parse strikethrough")
    func parseStrikethrough() {
        let md = "~~deleted~~"
        let result = parser.parse(md)
        #expect(result.contains("<del>"))
    }

    @Test("Parse fenced code block")
    func parseCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let result = parser.parse(md)
        #expect(result.contains("<code"))
    }

    @Test("Strip YAML front matter")
    func stripYAMLFrontMatter() {
        let md = "---\ntitle: Test\n---\n# Content"
        let result = parser.parse(md)
        #expect(!result.contains("title: Test"))
        #expect(result.contains("<h1>"))
    }

    @Test("Empty string returns empty")
    func parseEmpty() {
        let result = parser.parse("")
        #expect(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/nateober/markdown_editor && swift test --filter MarkdownParserTests 2>&1 | tail -20`
Expected: FAIL

**Step 3: Write implementation**

```swift
import Foundation
import libcmark_gfm

final class MarkdownParser {

    init() {
        cmark_gfm_core_extensions_ensure_registered()
    }

    func parse(_ markdown: String) -> String {
        let stripped = stripFrontMatter(markdown)
        return renderToHTML(stripped)
    }

    func extractFrontMatter(_ markdown: String) -> String? {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return nil }
        let content = markdown.dropFirst(4)
        guard let endRange = content.range(of: "\n---\n") ??
              content.range(of: "\n---\r\n") ??
              content.range(of: "\n---") else { return nil }
        return String(content[content.startIndex..<endRange.lowerBound])
    }

    private func stripFrontMatter(_ markdown: String) -> String {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else { return markdown }
        let content = markdown.dropFirst(4)
        if let endRange = content.range(of: "\n---\n") {
            return String(content[endRange.upperBound...])
        } else if let endRange = content.range(of: "\n---\r\n") {
            return String(content[endRange.upperBound...])
        } else if content.hasSuffix("\n---") {
            return ""
        }
        return markdown
    }

    private func renderToHTML(_ markdown: String) -> String {
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        let extensionNames = ["table", "strikethrough", "tasklist", "autolink"]
        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        markdown.withCString { ptr in
            cmark_parser_feed(parser, ptr, strlen(ptr))
        }

        guard let doc = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(doc) }

        guard let html = cmark_render_html(doc, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }

        return String(cString: html)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/nateober/markdown_editor && swift test --filter MarkdownParserTests 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add MarkdownEditor/Services/MarkdownParser.swift Tests/MarkdownParserTests.swift
git commit -m "feat: add MarkdownParser wrapping cmark-gfm with GFM extensions"
```

---

### Task 9: Preview HTML Template and CSS

**Files:**
- Create: `MarkdownEditor/Resources/preview.html`
- Create: `MarkdownEditor/Resources/preview-light.css`
- Create: `MarkdownEditor/Resources/preview-dark.css`

**Step 1: Create preview.html template**

A minimal HTML template with a `<div id="content">` and a `updateContent()` JS function that updates the content div safely using DOM methods (to avoid raw string injection). Includes a `<link>` to the theme CSS.

**Step 2: Create preview-light.css** GitHub-style light theme for rendered markdown.

**Step 3: Create preview-dark.css** GitHub-dark-style theme.

**Step 4: Update Package.swift to include resources**

Add to the executable target:
```swift
resources: [
    .copy("Resources")
]
```

**Step 5: Verify build and commit**

```bash
git add MarkdownEditor/Resources/ Package.swift
git commit -m "feat: add preview HTML template with light/dark CSS themes"
```

---

### Task 10: PreviewHTMLGenerator

**Files:**
- Create: `MarkdownEditor/Views/Preview/PreviewHTMLGenerator.swift`
- Test: `Tests/PreviewHTMLGeneratorTests.swift`

**Step 1: Write failing test** (test that `generateBody` returns HTML containing parsed elements)

**Step 2: Write implementation** - wraps MarkdownParser, generates body HTML for JS injection and full standalone HTML for export.

**Step 3: Run tests and commit**

```bash
git add MarkdownEditor/Views/Preview/PreviewHTMLGenerator.swift Tests/PreviewHTMLGeneratorTests.swift
git commit -m "feat: add PreviewHTMLGenerator for markdown-to-HTML conversion"
```

---

### Task 11: PreviewWebView

**Files:**
- Create: `MarkdownEditor/Views/Preview/PreviewWebView.swift`

**Step 1: Write implementation** - NSViewRepresentable wrapping WKWebView. Loads template on creation, updates content via JS `updateContent()` call on each text change. Coordinator tracks loading state and queues pending HTML.

**Step 2: Verify build and commit**

```bash
git add MarkdownEditor/Views/Preview/PreviewWebView.swift
git commit -m "feat: add WKWebView-based preview with JS content update"
```

---

### Task 12: View Modes and Wiring

**Files:**
- Create: `MarkdownEditor/Model/ViewMode.swift`
- Create: `MarkdownEditor/Views/EditorArea/SideBySideView.swift`
- Create: `MarkdownEditor/Views/EditorArea/ToggleView.swift`
- Create: `MarkdownEditor/Views/EditorArea/EditorContainerView.swift`
- Modify: `MarkdownEditor/Views/ContentView.swift`

**Step 1: Create ViewMode enum** (sideBySide, editorOnly, previewOnly)

**Step 2: Create SideBySideView** (HSplitView with MarkdownTextView and PreviewWebView)

**Step 3: Create ToggleView** (ZStack with opacity toggling)

**Step 4: Create EditorContainerView** (switches between modes)

**Step 5: Update ContentView** with toolbar segmented picker, debounced preview update pipeline (300ms), and view mode state.

**Step 6: Verify build and commit**

```bash
git add MarkdownEditor/Model/ViewMode.swift MarkdownEditor/Views/EditorArea/ MarkdownEditor/Views/ContentView.swift
git commit -m "feat: add view modes with debounced live preview pipeline"
```

---

### Task 13: Phase 2 Verification

Run all tests, manual verification in Xcode.

```bash
swift test && swift build
git tag v0.2.0-phase2
```

---

## Phase 3: Syntax Highlighting

**Goal:** Markdown syntax is color-highlighted in the editor pane.

### Task 14: HighlightTheme

**Files:**
- Create: `MarkdownEditor/Services/HighlightTheme.swift`

Light and dark color definitions for each markdown token type (headings at different sizes, bold, italic, inline code with background, links in blue, etc.). Uses `NSColor` and `NSFont`.

```bash
git add MarkdownEditor/Services/HighlightTheme.swift
git commit -m "feat: add HighlightTheme with light/dark color definitions"
```

---

### Task 15: SyntaxHighlighter

**Files:**
- Create: `MarkdownEditor/Services/SyntaxHighlighter.swift`
- Test: `Tests/SyntaxHighlighterTests.swift`

**Step 1: Write failing tests** (heading gets large font, bold gets bold font, inline code gets background, links get blue, code blocks exclude inner highlighting)

**Step 2: Write implementation** - regex-based highlighter with 14 patterns applied in priority order. Code blocks are tracked to exclude inner patterns. Operates on NSMutableAttributedString ranges.

**Step 3: Run tests and commit**

```bash
git add MarkdownEditor/Services/SyntaxHighlighter.swift Tests/SyntaxHighlighterTests.swift
git commit -m "feat: add regex-based syntax highlighter with 14 token types"
```

---

### Task 16: MarkdownTextStorage

**Files:**
- Create: `MarkdownEditor/Views/Editor/MarkdownTextStorage.swift`
- Modify: `MarkdownEditor/Views/Editor/MarkdownNSTextView.swift`
- Modify: `MarkdownEditor/Views/Editor/MarkdownTextView.swift`

**Step 1: Create MarkdownTextStorage** - NSTextStorage subclass. In `processEditing()`, extends edited range to full paragraph, calls SyntaxHighlighter.

**Step 2: Update MarkdownNSTextView** - add convenience init that accepts MarkdownTextStorage and sets up layout manager + text container.

**Step 3: Update MarkdownTextView** - create MarkdownTextStorage in `makeNSView`, use it for the text view.

**Step 4: Run all tests and commit**

```bash
git add MarkdownEditor/Views/Editor/MarkdownTextStorage.swift MarkdownEditor/Views/Editor/MarkdownNSTextView.swift MarkdownEditor/Views/Editor/MarkdownTextView.swift
git commit -m "feat: integrate MarkdownTextStorage for real-time syntax highlighting"
git tag v0.3.0-phase3
```

---

## Phase 4: View Modes (Complete)

Phase 4 was scoped as the three view modes. Side-by-side, editor-only, and preview-only were built in Task 12. Live inline WYSIWYG is deferred to v2.

```bash
git tag v0.4.0-phase4
```

---

## Phase 5: Vim Keybindings

**Goal:** Basic vim motions and modes in the editor.

### Task 17: VimMode and VimInputHandler

**Files:**
- Create: `MarkdownEditor/Model/VimMode.swift`
- Create: `MarkdownEditor/Views/Editor/VimInputHandler.swift`
- Test: `Tests/VimInputHandlerTests.swift`

**Step 1: Create VimMode enum** (normal, insert, visual, visualLine)

**Step 2: Write failing tests** for VimInputHandler:
- Initial mode is normal
- `i` enters insert mode
- Escape returns to normal
- `v` enters visual mode
- Count prefix accumulates (3j = motion down with count 3)
- `dd` produces delete-line
- `dw` produces delete-word
- Keys pass through in insert mode

**Step 3: Write VimInputHandler** - state machine with states: idle, awaitingMotion, awaitingChar, awaitingSecondKey. Returns `VimResult` enum describing what the editor should do. Handles:
- Mode changes (i, a, A, I, o, O, v, V, Escape)
- Motions (h, j, k, l, w, b, e, 0, $, ^, G, gg, {, }, %, f, t)
- Operators (d, c, y, >, <) with doubled-operator lines (dd, yy, cc)
- Count prefixes (3dw, d2w)
- Single commands (x, X, r, p, P, u, Ctrl+R, ., J)
- Search (/)

**Step 4: Run tests and commit**

```bash
git add MarkdownEditor/Model/VimMode.swift MarkdownEditor/Views/Editor/VimInputHandler.swift Tests/VimInputHandlerTests.swift
git commit -m "feat: add VimInputHandler state machine"
```

---

### Task 18: VimMotions and Integration

**Files:**
- Create: `MarkdownEditor/Views/Editor/VimMotions.swift`
- Modify: `MarkdownEditor/Views/Editor/MarkdownNSTextView.swift`

**Step 1: Create VimMotionExecutor** - translates VimMotion enum values to NSTextView cursor operations (moveForward, moveBackward, moveWordForward, etc.). Supports `extending` parameter for visual mode.

**Step 2: Add keyDown override to MarkdownNSTextView** - routes key events through VimInputHandler when vim is enabled. Dispatches VimResult to appropriate executor methods. Implements operator execution (delete range, yank range, change range). Maintains yank register.

**Step 3: Run all tests and commit**

```bash
git add MarkdownEditor/Views/Editor/VimMotions.swift MarkdownEditor/Views/Editor/MarkdownNSTextView.swift
git commit -m "feat: integrate vim motions and operators into editor"
git tag v0.5.0-phase5
```

---

## Phase 6: Extended Markdown + Status Bar

**Goal:** Math, diagrams, code highlighting in preview. Status bar.

### Task 19: Bundle JS Libraries

Download and bundle KaTeX, highlight.js, and Mermaid.js into `MarkdownEditor/Resources/`.

```bash
git add MarkdownEditor/Resources/katex/ MarkdownEditor/Resources/highlight/ MarkdownEditor/Resources/mermaid/
git commit -m "feat: bundle KaTeX, highlight.js, Mermaid.js for rich preview"
```

### Task 20: Update Preview for Extended Markdown

Update `preview.html` to load bundled JS libraries. Update `MarkdownParser` to wrap math delimiters for KaTeX and mermaid code blocks. Update `PreviewHTMLGenerator`.

```bash
git add MarkdownEditor/Resources/preview.html MarkdownEditor/Services/MarkdownParser.swift MarkdownEditor/Views/Preview/PreviewHTMLGenerator.swift
git commit -m "feat: enable math, diagrams, and code highlighting in preview"
```

### Task 21: StatusBarView

**Files:**
- Create: `MarkdownEditor/Views/StatusBar/StatusBarView.swift`
- Modify: `MarkdownEditor/Views/ContentView.swift`

Displays: vim mode badge (colored by mode), line:column, word count, character count, reading time. Wired into ContentView at the bottom.

```bash
git add MarkdownEditor/Views/StatusBar/StatusBarView.swift MarkdownEditor/Views/ContentView.swift
git commit -m "feat: add status bar with word count, reading time, vim mode"
git tag v0.6.0-phase6
```

---

## Phase 7: Folder Sidebar

### Task 22: File Tree Model and Sidebar View

**Files:**
- Create: `MarkdownEditor/Views/Sidebar/FileNode.swift`
- Create: `MarkdownEditor/Views/Sidebar/FolderTreeModel.swift`
- Create: `MarkdownEditor/Services/FileWatcher.swift`
- Create: `MarkdownEditor/Views/Sidebar/FolderSidebarView.swift`
- Modify: `MarkdownEditor/Views/ContentView.swift`
- Create: `MarkdownEditor/App/AppCommands.swift`

FileNode model, FolderTreeModel with @Observable, FileWatcher using DispatchSource, FolderSidebarView with OutlineGroup, "Open Folder" menu command.

```bash
git add MarkdownEditor/Views/Sidebar/ MarkdownEditor/Services/FileWatcher.swift MarkdownEditor/App/AppCommands.swift MarkdownEditor/Views/ContentView.swift
git commit -m "feat: add folder sidebar with directory tree browsing"
git tag v0.7.0-phase7
```

---

## Phase 8: Image Handling

### Task 23: ImageManager and Editor Integration

**Files:**
- Create: `MarkdownEditor/Services/ImageManager.swift`
- Test: `Tests/ImageManagerTests.swift`
- Modify: `MarkdownEditor/Views/Editor/MarkdownNSTextView.swift`

ImageManager saves images to `{doc}_images/`, returns relative path. Override paste() and drag-drop in MarkdownNSTextView. Configure WKWebView for local file access.

```bash
git add MarkdownEditor/Services/ImageManager.swift Tests/ImageManagerTests.swift MarkdownEditor/Views/Editor/MarkdownNSTextView.swift
git commit -m "feat: add image paste/drag with auto-save"
git tag v0.8.0-phase8
```

---

## Phase 9: Export

### Task 24: Export Services

**Files:**
- Create: `MarkdownEditor/Services/ExportService.swift`
- Create: `MarkdownEditor/Services/PDFExporter.swift`
- Create: `MarkdownEditor/Services/HTMLExporter.swift`
- Create: `MarkdownEditor/Services/DOCXExporter.swift`
- Modify: `Package.swift` (add DocX dependency)
- Modify: `MarkdownEditor/App/AppCommands.swift`

PDFExporter: off-screen WKWebView + createPDF(). HTMLExporter: standalone HTML with inlined CSS. DOCXExporter: AST walk to NSAttributedString via DocX library. ExportService facade with NSSavePanel. Export menu items.

```bash
git add MarkdownEditor/Services/Export* MarkdownEditor/Services/PDF* MarkdownEditor/Services/HTML* MarkdownEditor/Services/DOCX* Package.swift MarkdownEditor/App/AppCommands.swift
git commit -m "feat: add export to PDF, HTML, and DOCX"
git tag v0.9.0-phase9
```

---

## Phase 10: Find/Replace, Settings, Polish

### Task 25: Find and Replace

**Files:**
- Create: `MarkdownEditor/Views/Editor/FindReplaceView.swift`
- Create: `MarkdownEditor/Views/Editor/FindReplaceController.swift`

SwiftUI overlay bar, NSTextFinder integration, Cmd+F shortcut.

### Task 26: Settings Window

**Files:**
- Create: `MarkdownEditor/Model/EditorSettings.swift`
- Create: `MarkdownEditor/Views/SettingsView.swift`
- Modify: `MarkdownEditor/App/MarkdownEditorApp.swift`

@Observable with @AppStorage. Standard Settings scene (Cmd+,) with font size, vim toggle, default view mode.

### Task 27: Keyboard Shortcuts

Finalize `AppCommands.swift`:

| Shortcut | Action |
|----------|--------|
| Cmd+1 | Side-by-side mode |
| Cmd+2 | Editor-only mode |
| Cmd+3 | Preview-only mode |
| Cmd+\ | Toggle sidebar |
| Cmd+F | Find |
| Cmd+Shift+H | Replace |
| Cmd+Shift+E | Export submenu |
| Cmd+, | Settings |

### Task 28: Final Polish and Verification

- Verify macOS native tabbing
- Dark/light mode transitions
- Performance test with ~5000 line document
- Run full test suite

```bash
swift test && swift build
git tag v1.0.0
```

**End-to-end checklist:**
1. Open complex `.md` with headings, tables, code, math, mermaid, images, footnotes
2. Edit in side-by-side mode, verify live preview
3. Switch view modes via toolbar and Cmd+1/2/3
4. Vim keybindings: hjkl, dw, dd, yy, p, /, 3j
5. Cmd+F find and replace
6. Toggle folder sidebar, browse and open files
7. Paste image from clipboard, verify save and preview render
8. Export to PDF, HTML, DOCX and verify each
9. Switch light/dark mode
10. Merge windows into tabs
11. Open Settings, change font size, toggle vim
