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

    private struct ItemLayout {
        let origin: CGPoint
        let size: CGSize
    }

    private func calculateLayout(
        width proposedWidth: CGFloat?,
        subviews: Subviews
    ) -> (size: CGSize, items: [ItemLayout]) {
        let availableWidth = proposedWidth ?? .greatestFiniteMagnitude

        var items: [ItemLayout] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            items.append(ItemLayout(origin: CGPoint(x: x, y: y), size: size))

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            contentWidth = max(contentWidth, x - spacing)
        }

        let totalHeight = subviews.isEmpty ? 0 : y + rowHeight
        let totalWidth = proposedWidth ?? contentWidth

        return (CGSize(width: totalWidth, height: totalHeight), items)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        calculateLayout(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculateLayout(width: bounds.width, subviews: subviews)
        for (subview, item) in zip(subviews, result.items) {
            subview.place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
            )
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
    @State private var tagTranslations: [String: String] = [:]
    @State private var archivedIn: [APIClient.ArchivedInItem] = []
    @State private var archivedInLoaded = false
    @State private var coverData: Data?
    @State private var isFavorite = false
    @State private var isLoading = true
    @State private var relatedLoaded = false
    @State private var selectedTab = 0
    @State private var previewMode = 0
    @State private var isDescriptionExpanded = true
    @State private var previewImages: [Int: Data] = [:]
    @State private var previewLoading: [Int: Bool] = [:]
    @State private var showReader = false
    @State private var readerStartIndex = 0

    init(archive: SearchResultItem, server: Server) {
        self.archive = archive
        self.server = server

        // Load cached cover
        if let aid = archive.assets?.cover,
           let data = CacheManager.shared.getCover(id: "\(aid)") {
            _coverData = State(initialValue: data)
        }

        // Load cached tag translations
        let sid = server.baseURL
        if let cached = CacheManager.shared.getTagTranslations(serverId: sid),
           let map = try? JSONDecoder().decode([String: String].self, from: cached) {
            _tagTranslations = State(initialValue: map)
        }
    }

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
                                Button {
                                    readerStartIndex = 0
                                    showReader = true
                                } label: {
                                    Label(String(localized: "detail_start_read"), systemImage: "book.fill")
                                        .font(.subheadline).fontWeight(.semibold)
                                        .frame(maxWidth: .infinity).frame(height: 36)
                                        .background(Color.accentColor).foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
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
                
                if selectedTab != 0 && !isTankoubon {
                    Picker("", selection: $previewMode) {
                        Text(String(localized: "detail_preview")).tag(0)
                        Text(String(localized: "detail_filetree")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.3), value: selectedTab)
        .task { await loadData() }
        .fullScreenCover(isPresented: $showReader) {
            ReaderView(arcid: archive.arcid ?? "", files: files, startIndex: readerStartIndex, server: server)
        }
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

            if !isTankoubon {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "detail_archived_in"))
                        .font(.headline)
                    if !archivedInLoaded {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 8)
                    } else if archivedIn.isEmpty {
                        Text(String(localized: "no_archived_in"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(archivedIn, id: \.tankoubonId) { item in
                                    ArchiveGridCell(archive: item.asSearchResultItem, server: server).frame(width: 120)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

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
                        let child = children[i]
                        let dest = SearchResultItem(
                            type: "archive",
                            arcid: child.entityId,
                            tankoubonId: nil,
                            archivetype: nil,
                            filename: nil,
                            title: nil,
                            description: nil,
                            summary: nil,
                            pagecount: nil,
                            archiveCount: nil,
                            progress: nil,
                            size: nil,
                            tags: nil,
                            isnew: nil,
                            isfavorite: nil,
                            favoritetime: nil,
                            lastreadtime: nil,
                            assets: nil,
                            children: nil,
                            releaseAt: nil,
                            createdAt: nil,
                            updatedAt: nil
                        )
                        NavigationLink(value: dest) {
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
                        }
                        .buttonStyle(.plain)
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
                 .frame(height: previewMode == 0 ? nil : 0)
             FileTreeView(files: files)
                 .opacity(previewMode == 1 ? 1 : 0)
                 .allowsHitTesting(previewMode == 1)
                 .frame(height: previewMode == 1 ? nil : 0)
         }
     }

    private var previewGrid: some View {
        let mediaExts = Set(["mp3","wav","flac","aac","ogg","wma","m4a","aiff","mp4","mov","avi","mkv","webm","wmv","m4v","3gp"])
        let animExts = Set(["gif", "apng", "webp"])
        let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(files.indices, id: \.self) { i in
                let file = files[i]
                let path = file.defaultSource?.path ?? file.path ?? ""
                let ext = (path as NSString).pathExtension.lowercased()
                let isAnim = animExts.contains(ext)
                let isMedia = mediaExts.contains(ext)
                let mediaIcon: String? = isMedia ? (["mp4","mov","avi","mkv","webm","wmv","m4v","3gp"].contains(ext) ? "video.fill" : "music.note") : nil
                let badgeIcon: String? = isAnim ? "livephoto" : mediaIcon
                ArchivePreviewCell(
                    file: files[i],
                    index: i,
                    imageData: previewImages[i],
                    isLoading: previewLoading[i] ?? false,
                    mediaIcon: mediaIcon,
                    badgeIcon: badgeIcon
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
                if let cached = CacheManager.shared.getTankoubonMetadata(tankoubonId: id),
                   let cachedMeta = try? JSONDecoder().decode(APIClient.TankoubonMetadata.self, from: cached) {
                    tankoubonMeta = cachedMeta
                }
            }
        } else if let id = archive.arcid {
            let client = server.apiClient
            if let cached = CacheManager.shared.getArchiveMetadata(arcid: id),
               let cachedMeta = try? JSONDecoder().decode(APIClient.ArchiveMetadata.self, from: cached) {
                meta = cachedMeta
            }
            files = (try? await client.fetchFiles(arcid: id)) ?? []
            LogManager.shared.log("[Detail] Files loaded: \(files.count) for arcid=\(id)")
        }

        // Cover
        if isTankoubon {
            if let aid = archive.assets?.cover ?? tankoubonMeta?.coverAssetId { coverData = try? await fetchImage(assetId: aid) }
            else if let fc = archive.children?.first, let cm = try? await server.apiClient.fetchArchiveMetadata(arcid: fc), let aid = cm.coverAssetId { coverData = try? await fetchImage(assetId: aid) }
        } else {
            if let aid = archive.assets?.cover ?? meta?.coverAssetId { coverData = try? await fetchImage(assetId: aid) }
        }

        isLoading = false

        // Background refresh favorite status
        if isTankoubon, let id = archive.tankoubonId {
            tankoubonMeta = try? await server.apiClient.fetchTankoubonMetadata(tankoubonId: id, forceRefresh: true)
            isFavorite = tankoubonMeta?.isfavorite ?? isFavorite
        } else if let id = archive.arcid {
            let client = server.apiClient
            meta = try? await client.fetchArchiveMetadata(arcid: id, forceRefresh: true)
            isFavorite = meta?.isfavorite ?? isFavorite
        }

        // Fetch tag translations from server if not cached
        let serverId = server.baseURL
        if tagTranslations.isEmpty {
            if isTankoubon, let id = archive.tankoubonId {
                if let map = try? await server.apiClient.fetchTagTranslations(tankoubonId: id) {
                    tagTranslations = map
                    if let data = try? JSONEncoder().encode(map) { CacheManager.shared.cacheTagTranslations(serverId: serverId, data: data) }
                }
            } else if let id = archive.arcid {
                if let map = try? await server.apiClient.fetchTagTranslations(arcid: id) {
                    tagTranslations = map
                    if let data = try? JSONEncoder().encode(map) { CacheManager.shared.cacheTagTranslations(serverId: serverId, data: data) }
                }
            }
        }

        // Related
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
        if !archivedInLoaded, let id = archive.arcid {
            archivedIn = (try? await server.apiClient.fetchArchivedIn(arcid: id)) ?? []
            archivedInLoaded = true
        }
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
        if let cached = CacheManager.shared.getCover(id: "\(assetId)") {
            return cached
        }
        var urlString = server.baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else { return Data() }
        var req = URLRequest(url: url); req.httpMethod = "GET"
        if let t = server.authToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        let (d, r) = try await URLSession.shared.data(for: req)
        guard let h = r as? HTTPURLResponse, h.statusCode == 200 else { return Data() }
        CacheManager.shared.cacheCover(id: "\(assetId)", data: d)
        return d
    }

    private func toggleFavorite() {
        let wasFavorite = isFavorite
        isFavorite.toggle()
        Task {
            if isTankoubon, let id = archive.tankoubonId {
                if isFavorite { try? await server.apiClient.favoriteTankoubon(tankoubonId: id) }
                else { try? await server.apiClient.unfavoriteTankoubon(tankoubonId: id) }
                updateCachedFavorite(tankoubonId: id)
            } else if let id = archive.arcid {
                if isFavorite { try? await server.apiClient.favoriteArchive(arcid: id) }
                else { try? await server.apiClient.unfavoriteArchive(arcid: id) }
                updateCachedFavorite(arcid: id)
            }
            UserDefaults.standard.removeObject(forKey: "fav_cache")
        }
    }

    private func updateCachedFavorite(arcid: String) {
        guard var data = CacheManager.shared.getArchiveMetadata(arcid: arcid),
              var meta = try? JSONDecoder().decode(APIClient.ArchiveMetadata.self, from: data) else { return }
        meta.isfavorite = isFavorite
        if let encoded = try? JSONEncoder().encode(meta) {
            CacheManager.shared.cacheArchiveMetadata(arcid: arcid, data: encoded)
        }
    }

    private func updateCachedFavorite(tankoubonId: String) {
        guard var data = CacheManager.shared.getTankoubonMetadata(tankoubonId: tankoubonId),
              var meta = try? JSONDecoder().decode(APIClient.TankoubonMetadata.self, from: data) else { return }
        meta.isfavorite = isFavorite
        if let encoded = try? JSONEncoder().encode(meta) {
            CacheManager.shared.cacheTankoubonMetadata(tankoubonId: tankoubonId, data: encoded)
        }
    }

    private func parseTags() -> [String] {
        let raw: [String]
        if let t = meta?.tags ?? tankoubonMeta?.tags, !t.isEmpty { raw = t }
        else { raw = archive.tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? [] }
        if tagTranslations.isEmpty { return raw }
        return raw.map { tagTranslations[$0] ?? $0 }
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
        let ext = (path as NSString).pathExtension.lowercased()
        let mediaExts = ["mp3","wav","flac","aac","ogg","wma","m4a","aiff","mp4","mov","avi","mkv","webm","wmv","m4v","3gp"]

        if mediaExts.contains(ext) {
            let thumbId = file.defaultSource?.metadata?.thumbAssetId ?? file.metadata?.thumbAssetId ?? 0
            if thumbId > 0 {
                let cacheKey = "thumb_\(thumbId)"
                if let cached = CacheManager.shared.getCover(id: cacheKey) {
                    previewImages[index] = cached
                    return
                }
                do {
                    let data = try await client.fetchAsset(assetId: thumbId)
                    CacheManager.shared.cacheCover(id: cacheKey, data: data)
                    previewImages[index] = data
                } catch {
                    LogManager.shared.log("[Preview] thumb fetch failed index=\(index): \(error.localizedDescription)")
                }
            }
            return
        }

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
    let mediaIcon: String?
    let badgeIcon: String?

    var body: some View {
        Rectangle().fill(Color(.systemGray5))
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else if isLoading {
                    ProgressView()
                } else if let icon = mediaIcon {
                    Image(systemName: icon)
                        .font(.title)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "photo").foregroundColor(.secondary)
                }
            }
            .overlay(alignment: .topTrailing) {
                Text("\(index + 1)")
                    .font(.caption2)
                    .padding(.horizontal, index + 1 < 10 ? 8 : 6)
                    .padding(.vertical, 3)
                    .glassEffect(.regular)
                    .clipShape(Capsule())
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if let icon = badgeIcon, imageData != nil {
                    Image(systemName: icon)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .glassEffect(.regular)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

