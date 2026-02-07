import SwiftUI
import AppKit

/// Notification posted when a folder is selected via the Open Folder menu command.
/// The notification's object is the selected folder URL.
extension Notification.Name {
    static let openFolder = Notification.Name("com.markdownEditor.openFolder")
}

// MARK: - FocusedValue for Document Text

/// Key for passing the current document's markdown text to menu commands via @FocusedValue.
struct DocumentTextKey: FocusedValueKey {
    typealias Value = String
}

extension FocusedValues {
    var documentText: String? {
        get { self[DocumentTextKey.self] }
        set { self[DocumentTextKey.self] = newValue }
    }
}

/// Custom menu commands for the Markdown Editor app.
/// Provides an "Open Folder..." command and export submenu.
struct AppCommands: Commands {
    @FocusedValue(\.documentText) var documentText

    private let exportService = ExportService()

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder...") {
                openFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(after: .importExport) {
            Menu("Export") {
                Button("Export as PDF...") {
                    guard let text = documentText else { return }
                    let darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    exportService.exportPDF(markdown: text, darkMode: darkMode)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Export as HTML...") {
                    guard let text = documentText else { return }
                    let darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    exportService.exportHTML(markdown: text, darkMode: darkMode)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button("Export as Word...") {
                    guard let text = documentText else { return }
                    exportService.exportDOCX(markdown: text)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            .disabled(documentText == nil)
        }
    }

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.message = "Select a folder containing markdown files"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            NotificationCenter.default.post(name: .openFolder, object: url)
        }
    }
}
