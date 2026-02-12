import SwiftUI

/// Sidebar view that displays the file tree for an open folder.
/// Uses a ScrollView with custom tree rendering to avoid NSOutlineView
/// column width bugs that cause left-side clipping when the sidebar is resized.
struct FolderSidebarView: View {
    @Bindable var model: FolderTreeModel

    var body: some View {
        Group {
            if let rootNode = model.rootNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let children = rootNode.children {
                            ForEach(children) { child in
                                FileNodeRow(
                                    node: child,
                                    selectedURL: $model.selectedFileURL,
                                    depth: 0
                                )
                            }
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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

/// A single row in the file tree that handles both directories (with expand/collapse)
/// and files (with selection). Renders children recursively when expanded.
private struct FileNodeRow: View {
    let node: FileNode
    @Binding var selectedURL: URL?
    let depth: Int
    @State private var isExpanded = true

    private var isSelected: Bool {
        !node.isDirectory && selectedURL == node.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
                .padding(.leading, CGFloat(depth) * 16)
                .padding(.trailing, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
                        .padding(.horizontal, 4)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if node.isDirectory {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isExpanded.toggle()
                        }
                    } else {
                        selectedURL = node.url
                    }
                }

            if node.isDirectory && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileNodeRow(
                        node: child,
                        selectedURL: $selectedURL,
                        depth: depth + 1
                    )
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 4) {
            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            } else {
                Spacer()
                    .frame(width: 12)
            }

            Image(systemName: node.isDirectory ? "folder.fill" : "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(node.isDirectory ? .blue : .secondary)
                .frame(width: 16)

            Text(node.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(node.name)
        }
        .padding(.leading, 8)
    }
}
