import SwiftUI
import AppKit

/// Notification posted when a folder is selected via the Open Folder menu command.
/// The notification's object is the selected folder URL.
extension Notification.Name {
    static let openFolder = Notification.Name("com.markdownEditor.openFolder")
}

/// Custom menu commands for the Markdown Editor app.
/// Provides an "Open Folder..." command that presents an NSOpenPanel for directory selection.
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder...") {
                openFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
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
