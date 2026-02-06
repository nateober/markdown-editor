# PRFAQ: MarkdownEditor

---

## Press Release

### MarkdownEditor: A Mac-Native Markdown Editor for People Who Think in Plain Text

**Saint Paul, MN** — Today marks the release of MarkdownEditor, a lightweight, native macOS application for writing, previewing, and exporting Markdown documents. Built entirely in Swift and SwiftUI, MarkdownEditor gives keyboard-driven writers a fast, focused tool that handles everything from quick notes to complex technical documents with math equations, diagrams, and code — without ever leaving a single app or requiring an internet connection.

Most Markdown editors force a choice: simple and native, or powerful and slow. Lightweight editors lack support for LaTeX math, Mermaid diagrams, or vim keybindings. Full-featured options are Electron-based web apps disguised as desktop software, consuming hundreds of megabytes of memory to render text. Writers who work in Markdown daily — for documentation, notes, blog posts, technical writing — deserve a tool that is both capable and fast.

MarkdownEditor is a true macOS citizen. It launches instantly, uses native file dialogs, supports macOS tabs and dark mode, and feels like it belongs on your Mac. The editor provides real-time syntax highlighting, two view modes (side-by-side preview and full-screen toggle), and optional vim keybindings for keyboard-first editing. The preview renders GitHub-Flavored Markdown with extensions including tables, footnotes, task lists, LaTeX math via KaTeX, Mermaid diagrams, and syntax-highlighted code blocks. When the writing is done, documents export to PDF, HTML, or Word with sensible default styling — no configuration required.

"I wanted an editor that matched how I actually work," said the developer. "Vim motions for editing, instant preview for complex documents, and export that just works. Everything else was either too much or not enough."

MarkdownEditor is available as a free, open-source download for macOS 14 (Sonoma) and later.

---

## Frequently Asked Questions

### Customer FAQ

**Q: Why not just use VS Code with a Markdown extension?**
A: You can, and many people do. But VS Code is a general-purpose code editor running on Electron. It uses 300-500MB of RAM at idle. MarkdownEditor is purpose-built for Markdown, launches in under a second, uses a fraction of the memory, and integrates with macOS features (native tabs, dark mode, system font rendering, file dialogs) in ways that Electron apps cannot. If Markdown is your primary writing format, a dedicated tool is a better experience.

**Q: How does this compare to iA Writer, Typora, or Obsidian?**
A: iA Writer is beautiful but lacks vim keybindings, math rendering, and Mermaid diagram support. Typora provides great inline WYSIWYG but is Electron-based and closed-source. Obsidian is a knowledge management system, not a focused editor — it's powerful but complex and also Electron-based. MarkdownEditor occupies the gap: native Mac performance, vim-driven editing, and full technical writing support (math, diagrams, code) in a clean, minimal interface.

**Q: What Markdown features are supported?**
A: Full GitHub-Flavored Markdown plus extensions: headings, bold/italic/strikethrough, links, images, tables, task lists, fenced code blocks with syntax highlighting, footnotes, definition lists, LaTeX math (inline and block), Mermaid diagrams, and YAML front matter. If you can write it in Markdown, MarkdownEditor can render and export it.

**Q: Do the vim keybindings cover everything?**
A: They cover the core workflow: normal/insert/visual modes, motions (hjkl, w/b/e, 0/$, gg/G, f/t), operators (d/c/y/p), counts (d2w, 3j), text objects (iw, i", i(), the dot command for repeating, and / search. This covers roughly 90% of daily vim usage. Full ex-command mode and macros are not included. Vim mode is optional and toggled off by default.

**Q: What export formats are available?**
A: PDF, HTML, and Word (.docx). PDF output matches exactly what you see in the preview, including rendered math, diagrams, and syntax-highlighted code. HTML export produces a single self-contained file with embedded CSS. Word export creates a styled .docx with proper headings, formatting, and code blocks. All exports use sensible defaults with no configuration needed.

**Q: Does it work offline?**
A: Completely. All rendering libraries (KaTeX for math, Mermaid for diagrams, highlight.js for code) are bundled in the app. No internet connection is needed for any feature.

**Q: Can I use it for managing a folder of Markdown files?**
A: Yes. Beyond single-file editing, there is an optional folder sidebar that lets you browse and navigate a directory of Markdown files as a project. It watches for external file changes and updates in real time. This makes it usable for documentation repos, Zettelkasten-style note collections, or blog content directories.

**Q: What about images?**
A: You can paste images from the clipboard or drag files directly into the editor. Images are automatically saved to a folder alongside your Markdown document, and a relative image reference is inserted. URL-referenced images also work in the preview. No manual file management needed.

### Technical FAQ

**Q: Why SwiftUI + AppKit hybrid instead of pure SwiftUI?**
A: SwiftUI's TextEditor is too limited for a serious text editor — it lacks syntax highlighting hooks, custom key event handling, and the level of control needed for vim keybindings. NSTextView (AppKit) is a mature, full-featured text editing component that has been refined for over 20 years. We use SwiftUI for the application shell (window management, toolbar, sidebar, status bar) and NSTextView via NSViewRepresentable for the editor itself. WKWebView handles the preview. This gives us the best of both worlds: modern declarative UI where it excels, and battle-tested components where precision matters.

**Q: Why cmark-gfm over Apple's swift-markdown?**
A: Apple's swift-markdown is built on cmark-gfm internally but adds a Swift AST layer that is more useful for programmatic analysis than for HTML generation. For this editor, the primary need is fast markdown-to-HTML conversion for the live preview. cmark-gfm provides this directly via C interop, supports footnotes natively, and is the same parser GitHub uses in production. The performance difference is negligible, but the directness of the API is preferable.

**Q: How does syntax highlighting work without tree-sitter?**
A: A custom NSTextStorage subclass intercepts every text edit and triggers a regex-based highlighter on the affected paragraph range. Markdown syntax is regular enough that priority-ordered regex patterns (code blocks first, then headings, then inline formatting) produce accurate highlighting. Re-highlighting only the edited paragraph keeps performance under 1ms per keystroke even for large documents. Tree-sitter would be more correct for edge cases but adds significant complexity and a C dependency that isn't justified for a personal-use editor.

**Q: How does the vim implementation work?**
A: A state machine (`VimInputHandler`) consumes key events from an NSTextView subclass override of `keyDown()`. The state machine tracks the current mode, count prefix, pending operator, and register. Each vim command is decomposed into its components (count + operator + motion/text-object), and the motion calculates a target range which the operator acts upon. Vim operations are translated to native NSTextView methods (moveForward, deleteBackward, replaceCharacters, etc.). The dot command records the last editing command and replays it.

**Q: Why bundle JavaScript libraries instead of rendering natively?**
A: KaTeX, Mermaid, and highlight.js are mature, well-tested rendering libraries with thousands of edge cases already handled. Reimplementing LaTeX math rendering or diagram layout in Swift would take months and produce inferior results. Bundling these libraries inside a WKWebView is a pragmatic choice: the preview is already HTML-based, and the JS libraries add roughly 5MB to the app bundle in exchange for correct rendering of complex content. The same rendered output also powers PDF export via WKWebView's native `createPDF()` API, ensuring WYSIWYG fidelity.

**Q: What are the known limitations?**
A: Tables in Word (.docx) export are rendered as formatted monospace text rather than native Word tables, due to limitations in NSAttributedString-based DOCX generation. Live inline WYSIWYG editing is planned for v2 but not included in the initial release. The vim implementation covers core usage but not macros, registers beyond the default, or ex commands beyond basic search. Documents up to ~10,000 lines are the target performance envelope; extremely large files may see slower syntax highlighting.

**Q: Is there a Settings window?**
A: Yes. A standard macOS Settings window (Cmd+,) lets you configure the editor font and size, toggle vim mode, choose the default view mode, and adjust preview styling. Typography defaults to SF Mono in the editor and system sans-serif in the preview.
