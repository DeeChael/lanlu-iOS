import SwiftUI

struct FileTreeView: View {
    let files: [APIClient.PageFile]

    var body: some View {
        let tree = buildTree()
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tree.keys.sorted(), id: \.self) { folder in
                if folder.isEmpty {
                    ForEach(tree[folder] ?? [], id: \.path) { file in
                        fileRow(file, indent: 0)
                    }
                } else {
                    folderRow(folder, files: tree[folder] ?? [])
                }
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ name: String, files: [APIClient.PageFile]) -> some View {
        DisclosureGroup {
            ForEach(files, id: \.path) { file in
                fileRow(file, indent: 16)
            }
        } label: {
            Label(name, systemImage: "folder.fill")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func fileRow(_ file: APIClient.PageFile, indent: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: file.type == "folder" ? "folder.fill" : "doc.fill")
                .foregroundColor(.secondary)
                .font(.caption)
            Text(file.path ?? file.id ?? "---")
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.leading, indent)
    }

    private func buildTree() -> [String: [APIClient.PageFile]] {
        var tree: [String: [APIClient.PageFile]] = [:]
        for file in files {
            guard let path = file.path else { continue }
            if let slash = path.lastIndex(of: "/") {
                let folder = String(path[..<slash])
                var list = tree[folder] ?? []
                list.append(file)
                tree[folder] = list
            } else {
                var list = tree[""] ?? []
                list.append(file)
                tree[""] = list
            }
        }
        return tree
    }
}
