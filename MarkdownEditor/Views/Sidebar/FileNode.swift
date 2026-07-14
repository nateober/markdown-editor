import Foundation

/// Represents a file or directory node in a folder tree.
/// Only .md files and directories containing .md files are included.
struct FileNode: Identifiable, Hashable {
    /// Stable identity across tree rebuilds so SwiftUI preserves per-row
    /// state (e.g. expansion) when the watcher triggers a refresh.
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileNode]?

    init(name: String, url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = url.path
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    /// Recursively builds a FileNode tree from a directory URL.
    /// Filters to only include .md files and directories that contain .md
    /// files. Hidden entries are excluded by the directory enumeration
    /// (.skipsHiddenFiles), so a root folder that is itself hidden
    /// (e.g. ~/.notes) still works.
    static func buildTree(from url: URL) -> FileNode? {
        // Canonicalize the root once so every descendant's literal path is
        // canonical too; then only symlinked entries need resolving.
        return buildNode(from: url.resolvingSymlinksInPath(), ancestors: [])
    }

    /// `ancestors` holds the canonical paths of directories on the current
    /// recursion path only (passed by value, so siblings don't pollute each
    /// other). A symlink resolving into an ancestor is a cycle and is
    /// skipped; a symlink into a sibling subtree is fine and traversed.
    private static func buildNode(from url: URL, ancestors: Set<String>) -> FileNode? {
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }

        let name = url.lastPathComponent

        if isDir.boolValue {
            let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            let canonicalPath = isSymlink ? url.resolvingSymlinksInPath().path : url.path
            if ancestors.contains(canonicalPath) {
                return nil
            }
            var childAncestors = ancestors
            childAncestors.insert(canonicalPath)

            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            let childNodes = contents
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap { buildNode(from: $0, ancestors: childAncestors) }

            // Only include directories that contain at least one .md file (directly or nested)
            if childNodes.isEmpty {
                return nil
            }

            return FileNode(
                name: name,
                url: url,
                isDirectory: true,
                children: childNodes
            )
        } else {
            // Only include markdown files
            guard url.pathExtension.lowercased() == "md" else {
                return nil
            }

            return FileNode(
                name: name,
                url: url,
                isDirectory: false,
                children: nil
            )
        }
    }
}
