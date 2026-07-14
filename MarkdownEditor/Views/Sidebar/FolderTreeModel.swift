import Foundation
import Observation

/// Observable model that manages the folder tree state.
/// Holds the root FileNode, tracks the selected file, and watches for file system changes.
@Observable
final class FolderTreeModel {
    var rootNode: FileNode?
    var selectedFileURL: URL?
    var folderURL: URL?

    /// Incremented on every file click, so re-clicking the already-selected
    /// file still triggers an open (selectedFileURL alone wouldn't change).
    private(set) var openRequestCount = 0

    private var fileWatcher: FileWatcher?
    private var refreshGeneration = 0

    /// Loads a folder and builds the file tree.
    /// Sets up a file watcher to automatically refresh on changes.
    func loadFolder(at url: URL) {
        folderURL = url
        refresh()
        setupWatcher(for: url)
    }

    /// Records a request to open a file, even if it is already selected.
    func requestOpen(_ url: URL) {
        selectedFileURL = url
        openRequestCount += 1
    }

    /// Refreshes the file tree from the current folder URL.
    /// The directory walk runs off the main thread — the watcher can fire on
    /// every save, and a large tree would otherwise stall typing.
    func refresh() {
        guard let folderURL = folderURL else {
            rootNode = nil
            return
        }
        refreshGeneration += 1
        let generation = refreshGeneration
        Task.detached(priority: .utility) {
            let node = FileNode.buildTree(from: folderURL)
            await MainActor.run {
                // Drop stale results if a newer refresh started meanwhile.
                guard generation == self.refreshGeneration else { return }
                self.rootNode = node
            }
        }
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
