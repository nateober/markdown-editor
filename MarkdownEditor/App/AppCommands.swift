import SwiftUI
import AppKit

/// One-shot hand-off for Open Folder when no document window is focused:
/// AppCommands stashes the URL, opens an untitled document, and the new
/// window's ContentView consumes it in onAppear. Avoids broadcasting a
/// notification every window would react to (and the timing race of
/// posting before the new window subscribes).
enum FolderOpenRequest {
    static var pendingURL: URL?
}

// MARK: - FocusedValue for Open Folder

/// Action exposed by the focused document window so the Open Folder menu
/// command targets exactly that window's sidebar.
struct OpenFolderAction {
    let run: (URL) -> Void
}

struct OpenFolderActionKey: FocusedValueKey {
    typealias Value = OpenFolderAction
}

// MARK: - FocusedValue for Document Text

/// Key for passing the current document's markdown text to menu commands via @FocusedValue.
struct DocumentTextKey: FocusedValueKey {
    typealias Value = String
}

// MARK: - FocusedValue for View Mode

/// Key for setting the current view mode from menu commands.
struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

// MARK: - FocusedValue for Sidebar Visibility

/// Key for toggling sidebar visibility from menu commands.
struct SidebarVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var documentText: String? {
        get { self[DocumentTextKey.self] }
        set { self[DocumentTextKey.self] = newValue }
    }

    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }

    var sidebarVisible: Binding<Bool>? {
        get { self[SidebarVisibilityKey.self] }
        set { self[SidebarVisibilityKey.self] = newValue }
    }

    var openFolderAction: OpenFolderAction? {
        get { self[OpenFolderActionKey.self] }
        set { self[OpenFolderActionKey.self] = newValue }
    }
}

/// Custom menu commands for the Markdown Editor app.
/// Provides file commands, export, view mode switching, find/replace, and sidebar toggle.
struct AppCommands: Commands {
    @FocusedValue(\.documentText) var documentText
    @FocusedValue(\.viewMode) var viewMode
    @FocusedValue(\.sidebarVisible) var sidebarVisible
    @FocusedValue(\.openFolderAction) var openFolderAction

    private let exportService = ExportService()

    var body: some Commands {
        // MARK: - File Commands

        CommandGroup(after: .newItem) {
            Button("Open Folder...") {
                openFolderPanel()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        // MARK: - Export Commands

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

        // MARK: - View Mode Commands

        CommandMenu("View") {
            Button("Side by Side") {
                viewMode?.wrappedValue = .sideBySide
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Editor Only") {
                viewMode?.wrappedValue = .editorOnly
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Preview Only") {
                viewMode?.wrappedValue = .previewOnly
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Toggle Sidebar") {
                if let binding = sidebarVisible {
                    binding.wrappedValue.toggle()
                }
            }
            .keyboardShortcut("\\", modifiers: .command)
        }

        // MARK: - Find & Replace Commands

        CommandGroup(after: .textEditing) {
            Button("Find...") {
                triggerFindPanel(action: .showFindInterface)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Replace...") {
                triggerFindPanel(action: .showReplaceInterface)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])
        }
    }

    // MARK: - Private Helpers

    private func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.message = "Select a folder containing markdown files"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let action = openFolderAction {
                // A document window is focused: open the folder in it directly.
                action.run(url)
            } else {
                // No focused document window (none open, or Settings has
                // focus): stash the URL and open an untitled document whose
                // ContentView consumes it in onAppear.
                FolderOpenRequest.pendingURL = url
                try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            }
        }
    }

    /// Trigger the native NSTextView find panel on the key window's first responder.
    private func triggerFindPanel(action: NSTextFinder.Action) {
        guard let window = NSApp.keyWindow,
              let textView = window.firstResponder as? NSTextView else { return }
        textView.performTextFinderAction(action)
    }
}
