import SwiftUI

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
    @State private var selectedTab = 0
    @State private var previewMode = 0
    @State private var isDescriptionExpanded = false

    private var isTankoubon: Bool { archive.type == "tankoubon" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 12) {
                    coverView
                        .frame(width: 120)
                        .aspectRatio(3.0 / 4.0, contentMode: .fill)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        MarqueeText(text: archive.filename ?? archive.title ?? "---")
                            .font(.title3)
                            .fontWeight(.bold)
                            .lineLimit(2)

                        if isTankoubon {
                            if let ac = archive.archiveCount ?? tankoubonMeta?.archiveCount {
                                Text(String(format: String(localized: "tankoubon_archives"), ac))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Text(String(format: String(localized: "detail_total_pages"), tankoubonMeta?.pagecount ?? 0))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            if let pages = archive.pagecount ?? meta?.pagecount {
                                Text(String(format: String(localized: "detail_total_pages"), pages))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                toggleFavorite()
                            } label: {
                                Label(String(localized: "detail_favorite"), systemImage: isFavorite ? "heart.fill" : "heart")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)

                            if !isTankoubon {
                                Button(String(localized: "detail_start_read")) {
                                    // placeholder
                                }
                                .font(.subheadline)
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
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

                if selectedTab == 0 {
                    infoTab
                } else {
                    contentTab
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadData() }
    }

    // MARK: - Cover

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
            .overlay(alignment: .topLeading) {
                if isTankoubon {
                    Text(String(localized: "badge_tankoubon"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                        .padding(4)
                }
            }
            .clipped()
    }

    // MARK: - Info Tab

    private var infoTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description
            if let desc = archive.description ?? meta?.description, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "detail_description"))
                        .font(.headline)
                        .padding(.horizontal, 16)

                    Text(desc)
                        .font(.subheadline)
                        .lineLimit(isDescriptionExpanded ? nil : 3)
                        .padding(.horizontal, 16)

                    Button(isDescriptionExpanded ? String(localized: "detail_collapse") : String(localized: "detail_expand")) {
                        withAnimation { isDescriptionExpanded.toggle() }
                    }
                    .font(.caption)
                    .padding(.horizontal, 16)
                }
            }

            // Tags
            let tags = parseTags()
            if !tags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "detail_tags"))
                        .font(.headline)
                        .padding(.horizontal, 16)

                    TagFlowView(tags: .constant(tags.map { (value: $0, label: $0, display: $0) }), onTagRemoved: {})
                        .disabled(true)
                        .padding(.horizontal, 16)
                }
            }

            // Related
            if !related.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "detail_related"))
                        .font(.headline)
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(related, id: \.arcid) { item in
                                ArchiveGridCell(archive: item, server: server)
                                    .frame(width: 120)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // MARK: - Content Tab

    @ViewBuilder
    private var contentTab: some View {
        if isTankoubon {
            tankoubonContent
        } else {
            archiveContent
        }
    }

    private var tankoubonContent: some View {
        Group {
            if let children = tankoubonMeta?.children, !children.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(children.indices, id: \.self) { i in
                        let child = children[i]
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.entityId ?? "---")
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(String(format: String(localized: "detail_volume"), child.volumeNo ?? i + 1))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
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
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if previewMode == 0 {
                previewGrid
            } else {
                fileTreeView
            }
        }
    }

    private var previewGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(files.indices, id: \.self) { i in
                Button {
                    // placeholder: start reading from page i
                } label: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay(alignment: .topTrailing) {
                            Text("\(i + 1)")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(4)
                        }
                        .overlay {
                            if files[i].type == "image" {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }
        }
        .padding(16)
    }

    private var fileTreeView: some View {
        FileTreeView(files: files)
            .padding(.horizontal, 16)
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        if isTankoubon {
            if let id = archive.tankoubonId {
                tankoubonMeta = try? await server.apiClient.fetchTankoubonMetadata(tankoubonId: id)
                isFavorite = tankoubonMeta?.isfavorite ?? false
            }
        } else if let id = archive.arcid {
            async let metaData = server.apiClient.fetchArchiveMetadata(arcid: id)
            async let filesData = server.apiClient.fetchFiles(arcid: id)
            meta = try? await metaData
            files = (try? await filesData) ?? []
            isFavorite = meta?.isfavorite ?? false
        }

        // Load cover
        if isTankoubon {
            if let assetId = archive.assets?.cover {
                coverData = try? await fetchImage(assetId: assetId)
            } else if let meta = tankoubonMeta, let assetId = meta.coverAssetId {
                coverData = try? await fetchImage(assetId: assetId)
            } else if let firstChild = archive.children?.first {
                if let childMeta = try? await server.apiClient.fetchArchiveMetadata(arcid: firstChild),
                   let assetId = childMeta.coverAssetId {
                    coverData = try? await fetchImage(assetId: assetId)
                }
            }
        } else {
            if let assetId = archive.assets?.cover ?? meta?.coverAssetId {
                coverData = try? await fetchImage(assetId: assetId)
            }
        }

        // Load related
        if isTankoubon, let id = archive.tankoubonId {
            related = (try? await server.apiClient.fetchRecommendations(
                count: 10, scene: "tankoubon_related", tankoubonId: id
            )) ?? []
        } else if let id = archive.arcid {
            related = (try? await server.apiClient.fetchRecommendations(
                count: 10, scene: "archive_related", archiveId: id
            )) ?? []
        }

        isLoading = false
    }

    private func fetchImage(assetId: Int) async throws -> Data {
        var urlString = server.baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else { return Data() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = server.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return Data() }
        return data
    }

    private func toggleFavorite() {
        isFavorite.toggle()
    }

    private func parseTags() -> [String] {
        if let tags = meta?.tags ?? tankoubonMeta?.tags, !tags.isEmpty {
            return tags
        }
        return archive.tags?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
    }
}
