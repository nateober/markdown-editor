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
                baseURL: nil
            )

            Divider()

            StatusBarView(
                text: document.text,
                vimMode: vimMode,
                cursorPosition: cursorPosition
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
