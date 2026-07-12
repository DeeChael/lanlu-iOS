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
    @State private var previewImages: [Int: Data] = [:]
    @State private var previewLoading: [Int: Bool] = [:]

    private var isTankoubon: Bool { archive.type == "tankoubon" }

    var body: some View {
        VStack(spacing: 0) {
            

            // Scrollable content
            ScrollView {
                if selectedTab == 0 { infoTab } else { contentTab }
            }
        }
        .safeAreaBar(edge: .top) {
            VStack {
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
                
                if selectedTab != 0 && !isTankoubon {
                    Picker("", selection: $previewMode) {
                        Text(String(localized: "detail_preview")).tag(0)
                        Text(String(localized: "detail_filetree")).tag(1)
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                }
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
            // Description + Tags
            VStack(alignment: .leading, spacing: 8) {
                let descText = archive.description ?? meta?.description
                if let descText, !descText.isEmpty {
                    Text(descText).font(.subheadline)
                } else {
                    Text(String(localized: "detail_no_description"))
                        .font(.subheadline).italic().foregroundColor(.secondary)
                }
                let tags = parseTags()
                if !tags.isEmpty { DetailTagView(tags: tags) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "detail_related"))
                    .font(.headline)
                if !relatedLoaded {
                    HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 8)
                } else if related.isEmpty {
                    Text(String(localized: "no_related"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(related, id: \.displayId) { item in
                                ArchiveGridCell(archive: item, server: server).frame(width: 120)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                        HStack(spacing: 12) {
                            ChildCoverCell(child: children[i], index: i, server: server)
                                .frame(height: 128)
                                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 4) {
                                ChildMetaView(child: children[i], server: server)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if i < children.count - 1 { Divider().padding(.leading, 88) }
                    }
                }
            }
        }
    }

     private var archiveContent: some View {
         ZStack(alignment: .top) {
             previewGrid
                 .opacity(previewMode == 0 ? 1 : 0)
                 .allowsHitTesting(previewMode == 0)
             FileTreeView(files: files)
                 .opacity(previewMode == 1 ? 1 : 0)
                 .allowsHitTesting(previewMode == 1)
         }
     }

    private var previewGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(files.indices, id: \.self) { i in
                ArchivePreviewCell(
                    file: files[i],
                    index: i,
                    imageData: previewImages[i],
                    isLoading: previewLoading[i] ?? false
                )
            }
        }
        .padding(16)
        .task(id: files.count) {
            await loadPreviewImages()
        }
    }

    // MARK: - Data

    private func loadData() async {
        isLoading = true
        isFavorite = archive.isfavorite ?? false
        LogManager.shared.log("[Detail] loadData isTankoubon=\(isTankoubon) arcid=\(archive.arcid ?? "nil") tankoubonId=\(archive.tankoubonId ?? "nil")")
        if isTankoubon {
            if let id = archive.tankoubonId {
                tankoubonMeta = try? await server.apiClient.fetchTankoubonMetadata(tankoubonId: id)
                isFavorite = tankoubonMeta?.isfavorite ?? false
            }
        } else if let id = archive.arcid {
            let client = server.apiClient
            meta = try? await client.fetchArchiveMetadata(arcid: id)
            files = (try? await client.fetchFiles(arcid: id)) ?? []
            LogManager.shared.log("[Detail] Files loaded: \(files.count) for arcid=\(id)")
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
        var seen = Set<String>()
        var result: [SearchResultItem] = []
        for item in items {
            let id = item.arcid ?? item.tankoubonId ?? ""
            if id.isEmpty { continue }
            if id == archive.arcid || id == archive.tankoubonId { continue }
            if seen.contains(id) { continue }
            seen.insert(id)
            result.append(item)
            if result.count >= 10 { break }
        }
        return result
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
        let wasFavorite = isFavorite
        isFavorite.toggle()
        Task {
            if isTankoubon, let id = archive.tankoubonId {
                if isFavorite { try? await server.apiClient.favoriteTankoubon(tankoubonId: id) }
                else { try? await server.apiClient.unfavoriteTankoubon(tankoubonId: id) }
            } else if let id = archive.arcid {
                if isFavorite { try? await server.apiClient.favoriteArchive(arcid: id) }
                else { try? await server.apiClient.unfavoriteArchive(arcid: id) }
            }
            // Invalidate favorites cache
            UserDefaults.standard.removeObject(forKey: "fav_cache")
        }
    }

    private func parseTags() -> [String] {
        if let t = meta?.tags ?? tankoubonMeta?.tags, !t.isEmpty { return t }
        return archive.tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
    }

    private func loadPreviewImages() async {
        guard let arcid = archive.arcid else { return }
        let client = server.apiClient
        previewImages = [:]
        previewLoading = [:]

        let validIndices = files.indices.filter { i in
            let file = files[i]
            if (file.defaultSource?.path ?? file.path).map({ !$0.isEmpty }) == true {
                previewLoading[i] = true
                return true
            }
            return false
        }

        await withTaskGroup(of: Void.self) { group in
            var next = 0

            func enqueueNext() {
                guard next < validIndices.count else { return }
                let i = validIndices[next]
                next += 1
                group.addTask { [i] in
                    await loadSinglePreviewImage(index: i, arcid: arcid, client: client)
                }
            }

            for _ in 0..<min(2, validIndices.count) { enqueueNext() }

            for await _ in group {
                enqueueNext()
            }
        }
    }

    private func loadSinglePreviewImage(index: Int, arcid: String, client: APIClient) async {
        defer { previewLoading[index] = false }

        let file = files[index]
        let path = file.defaultSource?.path ?? file.path ?? ""
        let cacheKey = "page_\(arcid)_\(path)"

        if let cached = CacheManager.shared.getCover(id: cacheKey) {
            previewImages[index] = cached
            return
        }

        for attempt in 1...3 {
            guard !Task.isCancelled else { return }
            do {
                let data = try await client.fetchPageImage(arcid: arcid, path: path)
                CacheManager.shared.cacheCover(id: cacheKey, data: data)
                previewImages[index] = data
                return
            } catch {
                if Task.isCancelled { return }
                LogManager.shared.log("[Preview] attempt \(attempt)/3 failed index=\(index): \(error.localizedDescription)")
                if attempt < 3 { try? await Task.sleep(nanoseconds: 500_000_000) }
            }
        }
    }
}

struct ChildMetaView: View {
    let child: APIClient.TankoubonChild
    let server: Server
    @State private var archiveName: String?
    @State private var pagecount: Int?
    @State private var description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let name =  archiveName {
                Text(name)
                    .font(.subheadline).lineLimit(1)
            } else {
                Text(child.entityId ?? "---")
                    .font(.subheadline).lineLimit(1)
            }
            if let p = pagecount {
                Text("\(p) \(String(localized: "page_unit"))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let d = description, !d.isEmpty {
                Text(d).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
        }
        .task { await loadMeta() }
    }

    private func loadMeta() async {
        guard let eid = child.entityId else { print("[ChildMeta] no entityId"); return }
        guard let meta = try? await server.apiClient.fetchArchiveMetadata(arcid: eid) else { print("[ChildMeta] fetch failed for \(eid)"); return }
        archiveName = meta.title
        pagecount = meta.pagecount
        description = meta.description
        print("[ChildMeta] loaded \(eid): pages=\(meta.pagecount ?? 0) desc=\(meta.description?.prefix(30) ?? "nil")")
    }
}

struct ChildCoverCell: View {
    let child: APIClient.TankoubonChild
    let index: Int
    let server: Server
    @State private var coverData: Data?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                if let data = coverData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray5))
                        .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                }
            }
            .overlay(alignment: .topTrailing) {
                Text(String(format: String(localized: "detail_volume"), child.volumeNo ?? index + 1))
                    .font(.caption2).foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6)).clipShape(Capsule()).padding(4)
            }
            .clipped()
        .task { await loadCover() }
    }

    private func loadCover() async {
        guard let eid = child.entityId else {
            LogManager.shared.log("[Cover] child missing entityId")
            return
        }
        LogManager.shared.log("[Cover] loading cover for child entityId=\(eid)")
        guard let meta = try? await server.apiClient.fetchArchiveMetadata(arcid: eid),
              let aid = meta.coverAssetId else {
            LogManager.shared.log("[Cover] failed to get metadata or coverAssetId for \(eid)")
            return
        }
        LogManager.shared.log("[Cover] got coverAssetId=\(aid) for \(eid)")
        if let cached = CacheManager.shared.getCover(id: "\(aid)") { coverData = cached; LogManager.shared.log("[Cover] cache hit for \(aid)"); return }
        LogManager.shared.log("[Cover] cache miss, fetching asset from server")
        var urlString = server.baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(aid)") else {
            LogManager.shared.log("[Cover] invalid URL for asset \(aid)")
            return
        }
        LogManager.shared.log("[Cover] fetching \(url.absoluteString)")
        var req = URLRequest(url: url); req.httpMethod = "GET"
        if let t = server.authToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        guard let (d, r) = try? await URLSession.shared.data(for: req),
              let h = r as? HTTPURLResponse, h.statusCode == 200 else {
            LogManager.shared.log("[Cover] fetch failed for asset \(aid)")
            return
        }
        LogManager.shared.log("[Cover] fetched \(d.count) bytes for asset \(aid)")
        CacheManager.shared.cacheCover(id: "\(aid)", data: d)
        coverData = d
    }
}

struct ArchivePreviewCell: View {
    let file: APIClient.PageFile
    let index: Int
    let imageData: Data?
    let isLoading: Bool

    var body: some View {
        Rectangle().fill(Color(.systemGray5))
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo").foregroundColor(.secondary)
                }
            }
            .overlay(alignment: .topTrailing) {
                Text("\(index + 1)").font(.caption2).foregroundColor(.white)
                    .padding(4).background(Color.black.opacity(0.6)).clipShape(Capsule()).padding(4)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

