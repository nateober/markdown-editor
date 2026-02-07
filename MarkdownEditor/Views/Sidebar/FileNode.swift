import Foundation

/// Represents a file or directory node in a folder tree.
/// Only .md files and directories containing .md files are included.
struct FileNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let url: URL
    let isDirectory: Bool
    let children: [FileNode]?

    init(id: UUID = UUID(), name: String, url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    /// Recursively builds a FileNode tree from a directory URL.
    /// Filters to only include .md files and directories that contain .md files.
    /// Excludes hidden files (dotfiles) and .build/ directories.
    static func buildTree(from url: URL) -> FileNode? {
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return nil
        }

        let name = url.lastPathComponent

        // Skip hidden files and directories
        if name.hasPrefix(".") {
            return nil
        }

        if isDir.boolValue {
            // Skip .build directories
            if name == ".build" {
                return nil
            }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            let childNodes = contents
                .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap { buildTree(from: $0) }

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
