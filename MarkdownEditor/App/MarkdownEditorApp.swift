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
