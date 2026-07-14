import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var viewMode: ViewMode = .sideBySide
    @State private var previewHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var cursorLine: Int = 1
    @State private var cursorColumn: Int = 1
    @State private var vimMode: VimMode = .normal
    @State private var folderModel = FolderTreeModel()
    @State private var isSidebarVisible: Bool = false

    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("vimModeEnabled") private var vimModeEnabled: Bool = false
    @AppStorage("defaultViewMode") private var defaultViewModeRawValue: String = ViewMode.sideBySide.rawValue

    @Environment(\.openDocument) private var openDocument

    private let htmlGenerator = PreviewHTMLGenerator()

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            FolderSidebarView(model: folderModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            editorContent
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("View Mode", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch view mode")
            }
        }
        .onChange(of: document.text) { _, newValue in
            schedulePreviewUpdate(for: newValue)
        }
        .onAppear {
            // Apply the default view mode from settings on first appearance.
            if let mode = ViewMode(rawValue: defaultViewModeRawValue) {
                viewMode = mode
            }
            previewHTML = htmlGenerator.generateBody(from: document.text)
            // Consume a folder-open request handed off by AppCommands when no
            // document window was focused (this window was created for it).
            if let url = FolderOpenRequest.pendingURL {
                FolderOpenRequest.pendingURL = nil
                loadFolder(url)
            }
        }
        .onChange(of: folderModel.openRequestCount) { _, _ in
            if let url = folderModel.selectedFileURL {
                openFileInDocument(url)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .focusedValue(\.documentText, document.text)
        .focusedValue(\.viewMode, $viewMode)
        .focusedValue(\.sidebarVisible, $isSidebarVisible)
        .focusedValue(\.openFolderAction, OpenFolderAction { url in
            loadFolder(url)
        })
    }

    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isSidebarVisible ? .all : .detailOnly },
            set: { newValue in
                isSidebarVisible = (newValue != .detailOnly)
            }
        )
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            EditorContainerView(
                text: $document.text,
                viewMode: viewMode,
                htmlBody: previewHTML,
                baseURL: nil,
                fontSize: fontSize,
                vimEnabled: vimModeEnabled,
                onCursorChange: { line, column in
                    cursorLine = line
                    cursorColumn = column
                },
                onVimModeChange: { mode in
                    vimMode = mode
                }
            )

            Divider()

            StatusBarView(
                text: document.text,
                vimMode: vimMode,
                line: cursorLine,
                column: cursorColumn,
                vimEnabled: vimModeEnabled
            )
        }
    }

    private func schedulePreviewUpdate(for text: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled {
                await MainActor.run {
                    previewHTML = htmlGenerator.generateBody(from: text)
                }
            }
        }
    }

    private func loadFolder(_ url: URL) {
        folderModel.loadFolder(at: url)
        isSidebarVisible = true
    }

    private func openFileInDocument(_ url: URL) {
        // Open through the DocumentGroup machinery so the file gets its own
        // document (and window/tab) with the correct file association.
        // Overwriting document.text in place would discard the current
        // document's unsaved edits and leave Cmd+S pointed at the OLD file.
        Task { @MainActor in
            do {
                try await openDocument(at: url)
            } catch {
                showFileLoadError(error.localizedDescription, url: url)
            }
        }
    }

    private func showFileLoadError(_ message: String, url: URL) {
        guard let window = NSApp.keyWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Failed to Open File"
        alert.informativeText = "Could not open \"\(url.lastPathComponent)\": \(message)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
