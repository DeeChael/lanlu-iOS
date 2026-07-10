import SwiftUI

struct DetailTagView: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { y += s.height + spacing; x = 0 }
            x += s.width + spacing
            height = max(height, y + s.height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > width, x > bounds.minX { y += s.height + spacing; x = bounds.minX }
            sv.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
        }
    }
}

struct ArchiveDetailView: View {
    let archive: SearchResultItem
    let server: Server

    @State private var meta: APIClient.ArchiveMetadata?
    @State private var tankoubonMeta: APIClient.TankoubonMetadata?
    @State private var files: [APIClient.PageFile] = []
    @State private var related: [SearchResultItem] = []
    @State private var coverData: Data?
    @State private var isFavorite = false
    @State private var isLoading = true
    @State private var relatedLoaded = false
    @State private var selectedTab = 0
    @State private var previewMode = 0
    @State private var isDescriptionExpanded = true

    private var isTankoubon: Bool { archive.type == "tankoubon" }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            HStack(alignment: .top, spacing: 12) {
                coverView
                    .frame(width: 140)
                    .aspectRatio(3.0 / 4.0, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    MarqueeText(text: archive.filename ?? archive.title ?? "---")
                        .font(.title3)
                        .fontWeight(.bold)
                        .padding(.vertical, 2)

                    if isTankoubon {
                        if let ac = archive.archiveCount ?? tankoubonMeta?.archiveCount {
                            Text(String(format: String(localized: "tankoubon_archives"), ac))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(String(format: String(localized: "detail_total_pages"), tankoubonMeta?.pagecount ?? 0))
                            .font(.subheadline).foregroundColor(.secondary)
                    } else {
                        if let pages = archive.pagecount ?? meta?.pagecount {
                            Text(String(format: String(localized: "detail_total_pages"), pages))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button { toggleFavorite() } label: {
                            Image(systemName: isFavorite ? "heart.fill" : "heart").font(.body)
                        }
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())

                        if !isTankoubon {
                            Button {} label: {
                                Label(String(localized: "detail_start_read"), systemImage: "book.fill")
                                    .font(.subheadline).fontWeight(.semibold)
                                    .frame(maxWidth: .infinity).frame(height: 36)
                                    .background(Color.accentColor).foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .disabled(true)
                        }
                    }
                }
                .frame(height: 140 * 4 / 3)
            }
            .padding(16)

            // Segmented tabs
            Picker("", selection: $selectedTab) {
                Text(String(localized: "detail_info")).tag(0)
                Text(String(localized: "detail_content")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Scrollable content
            ScrollView {
                if selectedTab == 0 { infoTab } else { contentTab }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.3), value: selectedTab)
        .task { await loadData() }
    }

    @ViewBuilder
    private var coverView: some View {
        Rectangle()
            .fill(.clear)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = coverData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray5))
                        .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                }
            }
            .overlay(alignment: .topLeading) {
                if isTankoubon {
                    Text(String(localized: "badge_tankoubon"))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor).clipShape(Capsule()).padding(4)
                }
            }
            .clipped()
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            let descText = archive.description ?? meta?.description
            VStack(alignment: .leading, spacing: 8) {
                if let descText, !descText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(descText).font(.subheadline)
                            .lineLimit(isDescriptionExpanded ? nil : 4)

                        if isDescriptionExpanded {
                            let tags = parseTags()
                            if !tags.isEmpty { DetailTagView(tags: tags) }
                        } else {
                            let tags = parseTags()
                            if !tags.isEmpty { DetailTagView(tags: tags).lineLimit(1) }
                        }
                    }

                    if descText.count > 80 || !parseTags().isEmpty {
                        Button(isDescriptionExpanded ? String(localized: "detail_collapse") : String(localized: "detail_expand")) {
                            withAnimation { isDescriptionExpanded.toggle() }
                        }
                        .font(.caption)
                    }
                } else {
                    Text(String(localized: "detail_no_description"))
                        .font(.subheadline).italic().foregroundColor(.secondary)
                    let tags = parseTags()
                    if !tags.isEmpty { DetailTagView(tags: tags) }
                }
            }
            .padding(.horizontal, 16)

            if !relatedLoaded || !related.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "detail_related"))
                        .font(.headline)
                    if !relatedLoaded {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(related, id: \.arcid) { item in
                                    ArchiveGridCell(archive: item, server: server).frame(width: 120)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Content Tab

    @ViewBuilder
    private var contentTab: some View {
        if isTankoubon { tankoubonContent } else { archiveContent }
    }

    private var tankoubonContent: some View {
        Group {
            if let children = tankoubonMeta?.children, !children.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(children.indices, id: \.self) { i in
                        let c = children[i]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.entityId ?? "---").font(.subheadline).lineLimit(1)
                            Text(String(format: String(localized: "detail_volume"), c.volumeNo ?? i + 1))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if i < children.count - 1 { Divider().padding(.leading, 16) }
                    }
                }
            }
        }
    }

    private var archiveContent: some View {
        VStack(spacing: 0) {
            Picker("", selection: $previewMode) {
                Text(String(localized: "detail_preview")).tag(0)
                Text(String(localized: "detail_filetree")).tag(1)
            }
            .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)

            if previewMode == 0 { previewGrid } else { FileTreeView(files: files).padding(.horizontal, 16) }
        }
    }

    private var previewGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(files.indices, id: \.self) { i in
                Button {} label: {
                    Rectangle().fill(Color(.systemGray5))
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay(alignment: .topTrailing) {
                            Text("\(i + 1)").font(.caption2).foregroundColor(.white)
                                .padding(4).background(Color.black.opacity(0.6)).clipShape(Capsule()).padding(4)
                        }
                        .overlay {
                            if files[i].type == "image" {
                                Image(systemName: "photo").foregroundColor(.secondary)
                            }
                        }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        if isTankoubon {
            if let id = archive.tankoubonId {
                tankoubonMeta = try? await server.apiClient.fetchTankoubonMetadata(tankoubonId: id)
                isFavorite = tankoubonMeta?.isfavorite ?? false
            }
        } else if let id = archive.arcid {
            async let md = server.apiClient.fetchArchiveMetadata(arcid: id)
            async let fl = server.apiClient.fetchFiles(arcid: id)
            meta = try? await md; files = (try? await fl) ?? []
            isFavorite = meta?.isfavorite ?? false
        }
        if isTankoubon {
            if let aid = archive.assets?.cover ?? tankoubonMeta?.coverAssetId { coverData = try? await fetchImage(assetId: aid) }
            else if let fc = archive.children?.first, let cm = try? await server.apiClient.fetchArchiveMetadata(arcid: fc), let aid = cm.coverAssetId { coverData = try? await fetchImage(assetId: aid) }
        } else {
            if let aid = archive.assets?.cover ?? meta?.coverAssetId { coverData = try? await fetchImage(assetId: aid) }
        }
        // Related: fetch 40, deduplicate, remove self, keep 10
        if !relatedLoaded {
            if isTankoubon, let id = archive.tankoubonId {
                if let items = try? await server.apiClient.fetchRecommendations(count: 40, scene: "tankoubon_related", tankoubonId: id) {
                    related = processRelated(items)
                }
            } else if let id = archive.arcid {
                if let items = try? await server.apiClient.fetchRecommendations(count: 40, scene: "archive_related", archiveId: id) {
                    related = processRelated(items)
                }
            }
            relatedLoaded = true
        }
        isLoading = false
    }

    private func processRelated(_ items: [SearchResultItem]) -> [SearchResultItem] {
        var seenArcid = Set<String>()
        var seenTankoubon = Set<String>()
        return items.filter { item in
            if let aid = archive.arcid, item.arcid == aid { return false }
            if let tid = archive.tankoubonId, item.tankoubonId == tid { return false }
            if let id = item.arcid { guard !seenArcid.contains(id) else { return false }; seenArcid.insert(id) }
            if let id = item.tankoubonId { guard !seenTankoubon.contains(id) else { return false }; seenTankoubon.insert(id) }
            return true
        }.prefix(10).map { $0 }
    }

    private func fetchImage(assetId: Int) async throws -> Data {
        var urlString = server.baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else { return Data() }
        var req = URLRequest(url: url); req.httpMethod = "GET"
        if let t = server.authToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (d, r) = try await URLSession.shared.data(for: req)
        guard let h = r as? HTTPURLResponse, h.statusCode == 200 else { return Data() }
        return d
    }

    private func toggleFavorite() {
        isFavorite.toggle()
        Task {
            if isTankoubon, let id = archive.tankoubonId {
                if isFavorite { try? await server.apiClient.favoriteTankoubon(tankoubonId: id) }
                else { try? await server.apiClient.unfavoriteTankoubon(tankoubonId: id) }
            } else if let id = archive.arcid {
                if isFavorite { try? await server.apiClient.favoriteArchive(arcid: id) }
                else { try? await server.apiClient.unfavoriteArchive(arcid: id) }
            }
        }
    }

    private func parseTags() -> [String] {
        if let t = meta?.tags ?? tankoubonMeta?.tags, !t.isEmpty { return t }
        return archive.tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
    }
}
