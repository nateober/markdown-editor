import Foundation
import Observation

/// Observable model that manages the folder tree state.
/// Holds the root FileNode, tracks the selected file, and watches for file system changes.
@Observable
final class FolderTreeModel {
    var rootNode: FileNode?
    var selectedFileURL: URL?
    var folderURL: URL?

    private var fileWatcher: FileWatcher?

    /// Loads a folder and builds the file tree.
    /// Sets up a file watcher to automatically refresh on changes.
    func loadFolder(at url: URL) {
        folderURL = url
        refresh()
        setupWatcher(for: url)
    }

    /// Refreshes the file tree from the current folder URL.
    func refresh() {
        guard let folderURL = folderURL else {
            rootNode = nil
            return
        }
        rootNode = FileNode.buildTree(from: folderURL)
    }

    /// Closes the current folder and cleans up the watcher.
    func closeFolder() {
        fileWatcher = nil
        rootNode = nil
        selectedFileURL = nil
        folderURL = nil
    }

    private func setupWatcher(for url: URL) {
        fileWatcher = FileWatcher(url: url) { [weak self] in
            self?.refresh()
        }
    }
}
