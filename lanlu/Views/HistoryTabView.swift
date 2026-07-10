import SwiftUI

struct HistoryTabView: View {
    let server: Server
    @State private var archives: [SearchResultItem] = []
    @State private var isLoading = false
    @State private var hasMore = true

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        Group {
            if isLoading && archives.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if archives.isEmpty {
                ContentUnavailableView(
                    "history_placeholder",
                    systemImage: "clock.fill",
                    description: Text("history_placeholder_desc")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(archives, id: \.arcid) { archive in
                            ArchiveGridCell(archive: archive, server: server)
                                .onAppear { loadMoreIfNeeded(archive) }
                        }
                        if isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(12)
                }
            }
        }
        .navigationDestination(for: SearchResultItem.self) { item in
            ArchiveDetailView(archive: item, server: server)
        }
        .task { await loadHistory(reset: true) }
    }

    private func loadHistory(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset { archives = [] }

        do {
            let startOffset = archives.count
            let result = try await server.apiClient.fetchHistory(page: (startOffset / pageSize) + 1, pageSize: pageSize)
            let items = result.data ?? []

            var newCount = 0
            for item in items {
                if !archives.contains(where: { $0.arcid == item.arcid }) {
                    CacheManager.shared.cacheArchive(item)
                    archives.append(item)
                    newCount += 1
                }
            }

            hasMore = items.count == pageSize && (result.recordsTotal ?? 0) > archives.count
        } catch {
            hasMore = false
        }
        isLoading = false
    }

    private func loadMoreIfNeeded(_ archive: SearchResultItem) {
        guard hasMore, !isLoading,
              let index = archives.firstIndex(where: { $0.arcid == archive.arcid }),
              index >= archives.count - 5 else { return }
        Task { await loadHistory(reset: false) }
    }
}
