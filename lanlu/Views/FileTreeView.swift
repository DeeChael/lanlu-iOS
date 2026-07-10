import SwiftUI

struct FileTreeView: View {
    let files: [APIClient.PageFile]

    var body: some View {
        if files.isEmpty {
            Text(String(localized: "filetree_empty"))
                .font(.subheadline).foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(files.enumerated()), id: \.element.id) { _, file in
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .frame(width: 16)
                        Text(file.path ?? file.id ?? "---")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    Divider().padding(.leading, 24)
                }
            }
        }
    }
}
