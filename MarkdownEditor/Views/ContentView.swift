import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var viewMode: ViewMode = .sideBySide
    @State private var previewHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var cursorPosition: Int = 0
    @State private var vimMode: VimMode = .normal
    @State private var folderModel = FolderTreeModel()
    @State private var isSidebarVisible: Bool = false

    @AppStorage("editorFontSize") private var fontSize: Double = 14
    @AppStorage("vimModeEnabled") private var vimModeEnabled: Bool = false
    @AppStorage("defaultViewMode") private var defaultViewModeRawValue: String = ViewMode.sideBySide.rawValue

    private let htmlGenerator = PreviewHTMLGenerator()

    var body: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            FolderSidebarView(model: folderModel)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 350)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFolder)) { notification in
            if let url = notification.object as? URL {
                folderModel.loadFolder(at: url)
                isSidebarVisible = true
            }
        }
        .onChange(of: folderModel.selectedFileURL) { _, newURL in
            if let url = newURL {
                openFileInDocument(url)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .focusedValue(\.documentText, document.text)
        .focusedValue(\.viewMode, $viewMode)
        .focusedValue(\.sidebarVisible, $isSidebarVisible)
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
                vimEnabled: vimModeEnabled
            )

            Divider()

            StatusBarView(
                text: document.text,
                vimMode: vimMode,
                cursorPosition: cursorPosition,
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

    private func openFileInDocument(_ url: URL) {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return
        }
        document.text = content
    }
}
