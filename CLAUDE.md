# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build (debug)
swift build

# Build (release)
swift build -c release

# Run tests
swift test

# Run a single test
swift test --filter MarkdownEditorTests.VimInputHandlerTests

# Build .app bundle (output: build/MarkdownEditor.app)
./scripts/build-app.sh

# Build signed .app
./scripts/build-app.sh --sign

# Build signed + notarized .app
./scripts/build-app.sh --notarize

# Install to /Applications
cp -R build/MarkdownEditor.app /Applications/
```

## Architecture

This is a native macOS Markdown editor built with Swift Package Manager (not Xcode project). Requires macOS 14+.

### SwiftUI + AppKit Hybrid

The app uses SwiftUI for the shell (windows, toolbar, sidebar, settings) and AppKit for the core editor and preview:

- **MarkdownEditorApp** (`App/MarkdownEditorApp.swift`) - SwiftUI `@main` entry point using `DocumentGroup` with `ReferenceFileDocument`
- **MarkdownDocument** (`Model/MarkdownDocument.swift`) - `ReferenceFileDocument` with a single `@Published var text: String`
- **ContentView** (`Views/ContentView.swift`) - Main view composing sidebar, editor area, and status bar. Manages view mode, preview HTML generation (300ms debounce), and folder navigation

### Editor Stack (AppKit)

The editor is an `NSTextView` wrapped in `NSViewRepresentable`:

1. **MarkdownTextView** (`Views/Editor/MarkdownTextView.swift`) - `NSViewRepresentable` bridge; creates and syncs `NSScrollView` + `MarkdownNSTextView`
2. **MarkdownNSTextView** (`Views/Editor/MarkdownNSTextView.swift`) - `NSTextView` subclass handling vim key routing, image paste/drop, and cursor block rendering
3. **MarkdownTextStorage** (`Views/Editor/MarkdownTextStorage.swift`) - `NSTextStorage` subclass that triggers `SyntaxHighlighter` on every edit, re-highlighting the edited paragraph range
4. **SyntaxHighlighter** (`Services/SyntaxHighlighter.swift`) - Regex-based highlighter applied in priority order: front matter, fenced code blocks, then inline patterns. Uses `HighlightTheme` for colors

### Vim System

Vim keybindings are an optional layer intercepting `keyDown()` in `MarkdownNSTextView`:

- **VimInputHandler** (`Views/Editor/VimInputHandler.swift`) - Pure state machine (no AppKit dependency). Parses count + operator + motion/text-object, returns `VimResult` enum
- **VimMotions** (`Views/Editor/VimMotions.swift`) - Defines `VimMotion`, `VimOperator`, `VimResult` enums
- **VimMotionExecutor** (in `VimMotions.swift`) - Calculates target ranges from motions against a string

`VimInputHandler` is testable in isolation — tests feed key sequences and assert on `VimResult` values.

### Preview System

Preview uses a `WKWebView` loading bundled `Resources/preview.html`:

- **PreviewWebView** (`Views/Preview/PreviewWebView.swift`) - `NSViewRepresentable` wrapping `WKWebView`; calls `updateContent(html)` JS function on updates
- **PreviewHTMLGenerator** (`Views/Preview/PreviewHTMLGenerator.swift`) - Converts markdown to HTML body via `MarkdownParser`, also generates full standalone HTML documents for export
- **MarkdownParser** (`Services/MarkdownParser.swift`) - Wraps `libcmark_gfm` C library for GFM-to-HTML conversion with table, strikethrough, tasklist, autolink, and footnote extensions. Strips YAML front matter before parsing

Bundled JS libraries in `Resources/`: KaTeX (math), Mermaid (diagrams), highlight.js (code syntax)

### Export System

`ExportService` (`Services/ExportService.swift`) is a facade coordinating three exporters:

- **PDFExporter** - Renders HTML in an offscreen `WKWebView`, uses `createPDF()` for WYSIWYG output
- **HTMLExporter** - Generates self-contained HTML with inlined CSS
- **DOCXExporter** - Builds .docx ZIP archive using `NSAttributedString` with RTFD conversion

### View Modes & Commands

Three view modes (`Model/ViewMode.swift`): sideBySide, editorOnly, previewOnly. `EditorContainerView` switches between them.

`AppCommands` (`App/AppCommands.swift`) defines menu items using `@FocusedValue` to communicate between SwiftUI menus and the document window (export, view mode switching, find/replace, folder open, sidebar toggle).

### Settings

`EditorSettings` (`Model/EditorSettings.swift`) uses `@AppStorage` for persistence: font size, vim mode toggle, default view mode. `SettingsView` provides the Cmd+, preferences window.

### Folder Sidebar

`FolderSidebarView` + `FolderTreeModel` + `FileNode` provide a file browser for markdown directories. `FileWatcher` monitors the filesystem for external changes. The sidebar is toggled via Cmd+\ and opened via Cmd+Shift+O.

## Dependencies

- **libcmark_gfm** (0.29.4+) - GitHub-Flavored Markdown C parser
- **Yams** (5.0.0+) - YAML parsing (for front matter)

## Key Patterns

- Settings are persisted via `@AppStorage` (UserDefaults), not a settings file
- Menu commands communicate with document windows through `@FocusedValue` keys defined in `AppCommands.swift`
- The preview update is debounced at 300ms in `ContentView.schedulePreviewUpdate`
- `MarkdownTextStorage.processEditing()` modifies `backing` directly (not through `setAttributes`) to avoid infinite recursion
- Folder open uses `NotificationCenter` (`Notification.Name.openFolder`) to bridge between `AppCommands` and `ContentView`
