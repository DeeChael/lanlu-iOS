import SwiftUI

struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let isFolder: Bool
    let children: [FileNode]?

    static func build(from files: [APIClient.PageFile]) -> [FileNode] {
        var childrenOf: [String: Set<String>] = [:]
        var isDir = Set<String>()

        for file in files {
            let sourcePath = (file.defaultSource?.path ?? "").trimmingCharacters(in: .whitespaces)
            let fallbackPath = (file.path ?? "").trimmingCharacters(in: .whitespaces)
            let path = sourcePath.isEmpty ? fallbackPath : sourcePath
            guard !path.isEmpty else { continue }

            let parts = path.split(separator: "/").map(String.init)
            guard !parts.isEmpty else { continue }

            var parent = ""
            for (i, part) in parts.enumerated() {
                if i == parts.count - 1 {
                    childrenOf[parent, default: []].insert(part)
                } else {
                    let full = parent.isEmpty ? part : "\(parent)/\(part)"
                    isDir.insert(full)
                    childrenOf[parent, default: []].insert(part)
                    parent = full
                }
            }
        }

        func node(name: String, path: String) -> FileNode {
            let kids = (childrenOf[path] ?? []).map { child -> FileNode in
                let childPath = path.isEmpty ? child : "\(path)/\(child)"
                if isDir.contains(childPath) {
                    return node(name: child, path: childPath)
                }
                return FileNode(name: child, isFolder: false, children: nil)
            }.sorted { a, b in
                if a.isFolder != b.isFolder { return a.isFolder }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return FileNode(name: name, isFolder: true, children: kids.isEmpty ? nil : kids)
        }

        return (childrenOf[""] ?? []).map { name -> FileNode in
            if isDir.contains(name) {
                return node(name: name, path: name)
            }
            return FileNode(name: name, isFolder: false, children: nil)
        }.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

struct FileTreeView: View {
    let files: [APIClient.PageFile]
    private let rootNodes: [FileNode]

    init(files: [APIClient.PageFile]) {
        self.files = files
        self.rootNodes = FileNode.build(from: files)
    }

    var body: some View {
        if rootNodes.isEmpty {
            Text(String(localized: "filetree_empty"))
                .font(.subheadline).foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rootNodes) { node in
                    FileTreeRow(node: node, depth: 0)
                }
            }
            .padding(.horizontal)
        }
    }
}

private func iconForFile(_ name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif":
        return "photo.fill"
    case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
        return "archivebox.fill"
    case "pdf":
        return "doc.fill"
    case "txt", "md", "json", "xml", "html", "css", "js":
        return "doc.text.fill"
    case "mp4", "mov", "avi", "mkv", "webm":
        return "video.fill"
    case "mp3", "wav", "flac", "aac", "ogg":
        return "music.note"
    case "cbz", "cbr":
        return "book.fill"
    default:
        return "doc.fill"
    }
}

struct FileTreeRow: View {
    @State private var isExpanded = true
    let node: FileNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if node.isFolder {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }

                Image(systemName: node.isFolder
                    ? (isExpanded ? "folder.fill" : "folder")
                    : iconForFile(node.name))
                    .foregroundColor(node.isFolder ? .accentColor : .secondary)
                    .frame(width: 16)

                Text(node.name)
                    .font(.body)

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 24)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isFolder {
                    withAnimation(.default) { isExpanded.toggle() }
                }
            }

            if node.isFolder && isExpanded, let children = node.children {
                ForEach(children) { child in
                    FileTreeRow(node: child, depth: depth + 1)
                }
            }
        }
    }
}
