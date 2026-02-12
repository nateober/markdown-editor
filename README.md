# MarkdownEditor

A fast, native macOS Markdown editor with live preview, vim keybindings, and export to PDF, HTML, and Word.

Built with Swift and AppKit. No Electron. No web views for editing. Just a real Mac app.

## Download

**[Download the latest release](https://github.com/nateober/markdown-editor/releases/latest)** (macOS 14+)

1. Download **MarkdownEditor.dmg** from the link above
2. Open the DMG
3. Drag **MarkdownEditor** to your Applications folder
4. Open it from Applications

The app is signed and notarized by Apple, so it will open without any security warnings.

## Features

**Editor**
- Syntax-highlighted Markdown editing
- Find and replace (Cmd+F)
- Image paste and drag-and-drop

**Live Preview**
- Side-by-side, editor-only, or preview-only modes
- Math rendering with KaTeX
- Diagrams with Mermaid
- Code syntax highlighting

**Vim Mode**
- Optional vim keybindings (toggle in Settings)
- Motions, operators, text objects, visual mode, dot repeat

**Export**
- PDF (WYSIWYG from preview)
- HTML (self-contained, single file)
- Word (.docx with native tables)

**File Browser**
- Open a folder of Markdown files (Cmd+Shift+O)
- Tree view sidebar (Cmd+\\)

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+N | New document |
| Cmd+O | Open file |
| Cmd+S | Save |
| Cmd+F | Find and replace |
| Cmd+Shift+O | Open folder |
| Cmd+\\ | Toggle sidebar |
| Cmd+1 | Side-by-side view |
| Cmd+2 | Editor only |
| Cmd+3 | Preview only |
| Cmd+, | Settings |

## Build from Source

Requires macOS 14+ and Swift 5.9+.

```bash
# Clone
git clone https://github.com/nateober/markdown-editor.git
cd markdown-editor

# Build and run
swift build

# Run tests
swift test

# Build .app bundle
./scripts/build-app.sh

# Build signed + notarized .app (requires Apple Developer account)
./scripts/build-app.sh --notarize
```

## License

MIT
