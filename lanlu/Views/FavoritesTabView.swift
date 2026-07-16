import SwiftUI

struct FavoritesTabView: View {
    let server: Server
    @State private var items: [SearchResultItem] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var nextPage = 1

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("favorites_placeholder", systemImage: "heart.fill", description: Text("favorites_placeholder_desc"))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items, id: \.displayId) { item in
                            ArchiveGridCell(archive: item, server: server)
                                .id("\(item.displayId)-\(item.progress ?? 0)")
                                .onAppear { loadMoreIfNeeded(item) }
                        }
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(12)
                }
                .refreshable { await loadFavorites(reset: true) }
            }
        }
        .navigationDestination(for: SearchResultItem.self) { item in
            ArchiveDetailView(archive: item, server: server)
        }
        .task { await checkForUpdates() }
        .onAppear { syncProgressFromCache() }
        .onReceive(
            NotificationCenter.default.publisher(for: .readerProgressDidChange)
        ) { notification in
            applyReaderProgressChange(notification)
        }
    }

    private func syncProgressFromCache() {
        for index in items.indices {
            guard let arcid = items[index].arcid,
                  let cached = CacheManager.shared.getArchiveMetadata(arcid: arcid),
                  let meta = try? JSONDecoder().decode(
                    APIClient.ArchiveMetadata.self,
                    from: cached
                  ) else {
                continue
            }

            items[index].progress = meta.progress
        }
    }

    private func applyReaderProgressChange(_ notification: Notification) {
        guard notification.userInfo?["serverId"] as? String == server.baseURL,
              let arcid = notification.userInfo?["arcid"] as? String,
              let page = notification.userInfo?["page"] as? Int,
              let index = items.firstIndex(where: { $0.arcid == arcid }) else {
            return
        }

        items[index].progress = page
    }

    private func checkForUpdates() async {
        if items.isEmpty {
            await loadFavorites(reset: true)
            return
        }
        guard !isLoading else { return }
        isLoading = true
        if let result = try? await server.apiClient.search(favoriteOnly: true, groupbyTanks: true, sortby: "favoritetime", order: "desc", page: 1, pageSize: 20) {
            let newItems = result.data ?? []
            for item in newItems {
                if !items.contains(where: { $0.displayId == item.displayId }) {
                    items.append(item)
                }
            }
            LogManager.shared.log("[Favorites] Update check completed total=\(items.count)")
        }
        isLoading = false
    }

    private func loadFavorites(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset { items = []; nextPage = 1 }

        do {
            let result = try await server.apiClient.search(favoriteOnly: true, groupbyTanks: true, sortby: "favoritetime", order: "desc", page: nextPage, pageSize: pageSize)
            let newItems = result.data ?? []

            var added = 0
            for item in newItems {
                if !items.contains(where: { $0.displayId == item.displayId }) {
                    items.append(item)
                    added += 1
                }
            }

            LogManager.shared.log("[Favorites] Page loaded page=\(nextPage) received=\(newItems.count) added=\(added) total=\(items.count)")
            nextPage += 1
            hasMore = newItems.count >= pageSize
        } catch {
            LogManager.shared.log("[Favorites] Load failed: \(error.localizedDescription)")
            hasMore = false
        }

        isLoading = false
    }

    private func loadMoreIfNeeded(_ item: SearchResultItem) {
        guard hasMore, !isLoading,
              let idx = items.firstIndex(where: { $0.displayId == item.displayId }),
              idx >= items.count - 5 else { return }
        Task { await loadFavorites(reset: false) }
    }
}
