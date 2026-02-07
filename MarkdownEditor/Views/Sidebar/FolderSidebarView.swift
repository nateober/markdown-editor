import SwiftUI

/// Sidebar view that displays the file tree for an open folder.
/// Uses recursive disclosure groups to show directories and markdown files.
struct FolderSidebarView: View {
    @Bindable var model: FolderTreeModel

    var body: some View {
        Group {
            if let rootNode = model.rootNode {
                List(selection: $model.selectedFileURL) {
                    FileNodeView(node: rootNode, selectedURL: $model.selectedFileURL)
                }
                .listStyle(.sidebar)
            } else {
                ContentUnavailableView(
                    "No Folder Open",
                    systemImage: "folder",
                    description: Text("Use File > Open Folder to browse markdown files.")
                )
            }
        }
    }
}

/// Recursive view for rendering a single FileNode, expanding directories
/// as disclosure groups and showing files as selectable rows.
private struct FileNodeView: View {
    let node: FileNode
    @Binding var selectedURL: URL?

    var body: some View {
        if node.isDirectory {
            DisclosureGroup {
                if let children = node.children {
                    ForEach(children) { child in
                        FileNodeView(node: child, selectedURL: $selectedURL)
                    }
                }
            } label: {
                Label(node.name, systemImage: "folder")
            }
        } else {
            Label(node.name, systemImage: "doc.text")
                .tag(node.url)
                .onTapGesture {
                    selectedURL = node.url
                }
        }
    }
}
