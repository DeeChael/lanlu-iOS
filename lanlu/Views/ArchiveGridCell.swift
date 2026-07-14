import SwiftUI

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
                            .font(.subheadline).fontWeight(.bold).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.accentColor).clipShape(Capsule()).padding(4)
                    }
                }

            MarqueeText(text: isTankoubon ? (archive.title ?? "---") : (archive.filename ?? archive.title ?? "---"))
                .font(.subheadline).lineLimit(1)

            HStack(spacing: 4) {
                if isTankoubon {
                    if let count = archive.archiveCount {
                        Text(String(format: String(localized: "tankoubon_archives"), count))
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    if let pages = archive.pagecount {
                        Text("\(pages) \(String(localized: "page_unit"))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if !isTankoubon {
                    Text("\(progressPercent)%")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.primary)
                }
            }
            }
            .task { await loadCover() }
            }
            .tint(.primary)
    }

    @ViewBuilder
    private var coverView: some View {
        Rectangle().fill(.clear).aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                if let data = coverData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(.systemGray5))
                        .overlay { Image(systemName: "photo").foregroundColor(.secondary) }
                }
            }
            .clipped().clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func loadCover() async {
        if isTankoubon {
            if let aid = coverAssetId { await loadCoverImage(assetId: aid) }
            else { await loadTankoubonCover() }
        } else {
            await loadCoverImage(assetId: coverAssetId)
        }
    }

    private func loadCoverImage(assetId: Int?) async {
        guard let aid = assetId else { return }
        if let cached = CacheManager.shared.getCover(id: "\(aid)") { coverData = cached; return }
        guard let data = await fetchAsset(assetId: aid) else { return }
        CacheManager.shared.cacheCover(id: "\(aid)", data: data)
        coverData = data
    }

    private func loadTankoubonCover() async {
        guard let firstChild = archive.children?.first else { return }
        guard let meta = try? await server.apiClient.fetchArchiveMetadata(arcid: firstChild),
              let aid = meta.coverAssetId else { return }
        if let cached = CacheManager.shared.getCover(id: "\(aid)") { coverData = cached; return }
        guard let data = await fetchAsset(assetId: aid) else { return }
        CacheManager.shared.cacheCover(id: "\(aid)", data: data)
        coverData = data
    }

    private func fetchAsset(assetId: Int) async -> Data? {
        var urlString = server.baseURL
        if !urlString.contains("://") { urlString = "https://" + urlString }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else { return nil }
        var req = URLRequest(url: url); req.httpMethod = "GET"
        if let t = server.authToken { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        guard let (d, r) = try? await URLSession.shared.data(for: req),
              let h = r as? HTTPURLResponse, h.statusCode == 200 else { return nil }
        return d
    }
}

struct MarqueeText: View {
    let text: String
    @State private var offset: CGFloat = 0
    @State private var needsScroll = false

    var body: some View {
        GeometryReader { geo in
            Text(text).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .offset(x: needsScroll ? offset : 0)
                .onAppear { startMarquee(textWidth: geo.size.width) }
        }
        .frame(height: 24).clipped()
    }

    private func startMarquee(textWidth: CGFloat) {
        let estimatedWidth = (text as NSString).size(withAttributes: [.font: UIFont.preferredFont(forTextStyle: .body)]).width
        guard estimatedWidth > textWidth else { return }
        needsScroll = true
        withAnimation(.linear(duration: Double(estimatedWidth) / 30).delay(1).repeatForever(autoreverses: false)) {
            offset = textWidth - estimatedWidth - 20
        }
    }
}
