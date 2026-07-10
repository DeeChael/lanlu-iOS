import SwiftUI

struct FavoritesTabView: View {
    let server: Server
    @State private var archives: [SearchResultItem] = []
    @State private var tankoubons: [SearchResultItem] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var hasMoreArchives = true
    @State private var hasMoreTankoubons = true

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let favCacheKey = "fav_cache"

    private var allItems: [SearchResultItem] {
        (archives + tankoubons).sorted { ($0.favoritetime ?? 0) > ($1.favoritetime ?? 0) }
    }

    var body: some View {
        Group {
            if isLoading && allItems.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allItems.isEmpty {
                ContentUnavailableView("favorites_placeholder", systemImage: "heart.fill", description: Text("favorites_placeholder_desc"))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(allItems, id: \.displayId) { item in
                            ArchiveGridCell(archive: item, server: server)
                        }
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(12)
                }
                .refreshable {
                    await refreshAll()
                }
            }
        }
        .navigationDestination(for: SearchResultItem.self) { item in
            ArchiveDetailView(archive: item, server: server)
        }
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        loadFromCache()
        if !allItems.isEmpty { return }
        isLoading = true
        await fetchAll()
        isLoading = false
    }

    private func refreshAll() async {
        isRefreshing = true
        await fetchAll()
        isRefreshing = false
    }

    private func fetchAll() async {
        print("[Favorites] Fetching all favorites")
        var allArchives: [SearchResultItem] = []
        var allTankoubons: [SearchResultItem] = []
        var page = 1
        var maxPages = 10

        while page <= maxPages {
            if let r = try? await server.apiClient.fetchFavoritesArchives(page: page, pageSize: pageSize) {
                let items = r.data ?? []
                if items.isEmpty { break }
                var newCount = 0
                for item in items {
                    if !allArchives.contains(where: { $0.displayId == item.displayId }) {
                        allArchives.append(item)
                        newCount += 1
                    }
                }
                if newCount == 0 || items.count < pageSize { break }
                page += 1
            } else { break }
        }

        page = 1
        while page <= maxPages {
            if let r = try? await server.apiClient.fetchFavoritesTankoubons(page: page, pageSize: pageSize) {
                let items = r.data ?? []
                if items.isEmpty { break }
                var newCount = 0
                for item in items {
                    if !allTankoubons.contains(where: { $0.displayId == item.displayId }) {
                        allTankoubons.append(item)
                        newCount += 1
                    }
                }
                if newCount == 0 || items.count < pageSize { break }
                page += 1
            } else { break }
        }

        print("[Favorites] Fetched: archives=\(allArchives.count) tankoubons=\(allTankoubons.count)")
        archives = allArchives
        tankoubons = allTankoubons
        saveToCache()
    }

    private func loadFromCache() {
        guard let data = UserDefaults.standard.data(forKey: favCacheKey),
              let cached = try? JSONDecoder().decode(CachedFavorites.self, from: data) else { return }
        archives = cached.archives
        tankoubons = cached.tankoubons
        print("[Favorites] Cache loaded: archives=\(archives.count) tankoubons=\(tankoubons.count)")
    }

    private func saveToCache() {
        let cached = CachedFavorites(archives: archives, tankoubons: tankoubons)
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: favCacheKey)
        }
    }
}

private struct CachedFavorites: Codable {
    let archives: [SearchResultItem]
    let tankoubons: [SearchResultItem]
}

struct ArchiveGridCell: View {
    let archive: SearchResultItem
    let server: Server
    @State private var coverData: Data?

    private var isTankoubon: Bool { archive.type == "tankoubon" }
    private var coverAssetId: Int? { archive.assets?.cover }
    private var progressPercent: Int {
        guard !isTankoubon, let p = archive.progress, let total = archive.pagecount, total > 0 else { return 0 }
        return min(Int((Double(p) / Double(total)) * 100), 100)
    }

    var body: some View {
        NavigationLink(value: archive) {
            VStack(alignment: .leading, spacing: 4) {
            coverView
                .overlay(alignment: .topLeading) {
                    if isTankoubon {
                        Text(String(localized: "badge_tankoubon"))
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .padding(4)
                    }
                }

            MarqueeText(text: isTankoubon ? (archive.title ?? "---") : (archive.filename ?? archive.title ?? "---"))
                .font(.subheadline)
                .lineLimit(1)

            HStack(spacing: 4) {
                if isTankoubon {
                    if let count = archive.archiveCount {
                        Text(String(format: String(localized: "tankoubon_archives"), count))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    if let pages = archive.pagecount {
                        Text("\(pages) \(String(localized: "page_unit"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if !isTankoubon {
                    Text("\(progressPercent)%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            }
            .task { await loadCover() }
            }
            .tint(.primary)
    }

    @ViewBuilder
    private var coverView: some View {
        Rectangle()
            .fill(.clear)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = coverData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func loadCover() async {
        if isTankoubon {
            if let assetId = coverAssetId {
                await loadCoverImage(assetId: assetId)
            } else {
                await loadTankoubonCover()
            }
        } else {
            await loadCoverImage(assetId: coverAssetId)
        }
    }

    private func loadCoverImage(assetId: Int?) async {
        guard let assetId else { return }
        if let cached = CacheManager.shared.getCover(id: "\(assetId)") {
            coverData = cached; return
        }
        guard let data = await fetchAsset(assetId: assetId) else { return }
        CacheManager.shared.cacheCover(id: "\(assetId)", data: data)
        coverData = data
    }

    private func loadTankoubonCover() async {
        guard let firstChild = archive.children?.first else { return }
        do {
            let meta = try await server.apiClient.fetchArchiveMetadata(arcid: firstChild)
            guard let assetId = meta.coverAssetId else { return }
            if let cached = CacheManager.shared.getCover(id: "\(assetId)") {
                coverData = cached; return
            }
            guard let data = await fetchAsset(assetId: assetId) else { return }
            CacheManager.shared.cacheCover(id: "\(assetId)", data: data)
            coverData = data
        } catch {}
    }

    private func fetchAsset(assetId: Int) async -> Data? {
        var urlString = server.baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = server.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, resp) = try? await URLSession.shared.data(for: request),
              let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else { return nil }
        return data
    }
}

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var needsScroll = false

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: needsScroll ? offset : 0)
                .onAppear { startMarquee(textWidth: geo.size.width) }
        }
        .frame(height: 24)
        .clipped()
    }

    private func startMarquee(textWidth: CGFloat) {
        let fullWidth = CGFloat(text.count) * 10
        guard fullWidth > textWidth else { return }
        needsScroll = true
        withAnimation(.linear(duration: Double(fullWidth) / 30).delay(1).repeatForever(autoreverses: false)) {
            offset = textWidth - fullWidth - 20
        }
    }
}

