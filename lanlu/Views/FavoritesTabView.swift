import SwiftUI

struct FavoritesTabView: View {
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
                    "favorites_placeholder",
                    systemImage: "heart.fill",
                    description: Text("favorites_placeholder_desc")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(archives, id: \.displayId) { archive in
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
        .task { await loadFavorites(reset: true) }
    }

    private func loadFavorites(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset { archives = [] }

        do {
            let startOffset = archives.count
            let items = try await server.apiClient.fetchFavorites(start: startOffset, count: pageSize)

            var newCount = 0
            for item in items {
                if !archives.contains(where: { $0.displayId == item.displayId }) {
                    CacheManager.shared.cacheArchive(item)
                    archives.append(item)
                    newCount += 1
                }
            }

            hasMore = items.count >= pageSize
        } catch {
            print("[Favorites] Error: \(error)")
            hasMore = false
        }
        isLoading = false
    }

    private func loadMoreIfNeeded(_ archive: SearchResultItem) {
        guard hasMore, !isLoading,
              let index = archives.firstIndex(where: { $0.displayId == archive.displayId }),
              index >= archives.count - 5 else { return }
        Task { await loadFavorites(reset: false) }
    }
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
            }
            .task { await loadCover() }
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
