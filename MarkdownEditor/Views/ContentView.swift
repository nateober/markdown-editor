import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    @State private var viewMode: ViewMode = .sideBySide
    @State private var previewHTML: String = ""
    @State private var debounceTask: Task<Void, Never>?

    private let htmlGenerator = PreviewHTMLGenerator()

    var body: some View {
        EditorContainerView(
            text: $document.text,
            viewMode: viewMode,
            htmlBody: previewHTML,
            baseURL: nil
        )
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
        .frame(minWidth: 600, minHeight: 400)
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
}
