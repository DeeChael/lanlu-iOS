import SwiftUI

struct ServerStatisticsView: View {
    let server: Server

    @State private var serverInfo: ServerInfo?
    @State private var tagCloud: APIClient.TagCloudData?
    @State private var isLoadingInfo = true
    @State private var isLoadingCloud = true
    @State private var infoError: String?
    @State private var cloudError: String?

    var body: some View {
        List {
            Section(String(localized: "statistics_system_info")) {
                if let serverInfo {
                    informationRow(
                        String(localized: "statistics_server_name"),
                        value: serverInfo.name
                    )
                    informationRow(
                        String(localized: "statistics_version"),
                        value: serverInfo.versionDesc
                    )
                    informationRow(
                        String(localized: "statistics_total_archives"),
                        value: serverInfo.totalArchives.formatted()
                    )
                    informationRow(
                        String(localized: "statistics_total_pages_read"),
                        value: serverInfo.totalPagesRead.formatted()
                    )

                    HStack(alignment: .top) {
                        Text(String(localized: "statistics_db_extensions"))
                        Spacer(minLength: 12)
                        StatisticsWrappingLayout(
                            alignment: .trailing,
                            horizontalSpacing: 5,
                            verticalSpacing: 5
                        ) {
                            ForEach(serverInfo.dbExtensions, id: \.name) { item in
                                Text(item.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        .frame(width: 220, alignment: .trailing)
                    }

                    if !serverInfo.motd.isEmpty {
                        Text(serverInfo.motd)
                    }
                } else if isLoadingInfo {
                    loadingRow
                } else if let infoError {
                    errorRow(infoError)
                }
            }

            Section(String(localized: "statistics_tag_cloud")) {
                if let tagCloud, !tagCloud.items.isEmpty {
                    StatisticsWrappingLayout(
                        alignment: .center,
                        horizontalSpacing: 4,
                        verticalSpacing: 0
                    ) {
                        ForEach(cloudItems) { item in
                            Text(item.display.isEmpty ? item.tag : item.display)
                                .font(.system(size: fontSize(for: item.count), weight: .bold))
                                .foregroundStyle(cloudColor(for: item.tag))
                                .fixedSize()
                                .accessibilityLabel("\(item.display), \(item.count)")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else if isLoadingCloud {
                    loadingRow
                } else if let cloudError {
                    errorRow(cloudError)
                }
            }
        }
        .task {
            async let infoRequest: Void = loadServerInfo()
            async let cloudRequest: Void = loadTagCloud()
            _ = await (infoRequest, cloudRequest)
        }
    }

    private func informationRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
    }

    private func errorRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func fontSize(for count: Int) -> CGFloat {
        guard let items = tagCloud?.items,
              let minimum = items.map(\.count).min(),
              let maximum = items.map(\.count).max(),
              maximum > minimum else { return 16 }

        let lower = log(Double(max(minimum, 1)))
        let upper = log(Double(maximum))
        let value = log(Double(max(count, 1)))
        let progress = (value - lower) / max(upper - lower, 0.001)
        return 11 + CGFloat(progress) * 18
    }

    private var cloudItems: [APIClient.TagCloudItem] {
        tagCloud?.items.sorted {
            stableCloudOrder($0.tag) < stableCloudOrder($1.tag)
        } ?? []
    }

    private func stableCloudOrder(_ value: String) -> UInt64 {
        value.utf8.reduce(1_469_598_103_934_665_603) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private func cloudColor(for tag: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo]
        let index = tag.unicodeScalars.reduce(0) { $0 + Int($1.value) } % colors.count
        return colors[index]
    }

    @MainActor
    private func loadServerInfo() async {
        do {
            serverInfo = try await server.apiClient.fetchServerInfo()
            LogManager.shared.log("[Statistics] Server info loaded")
        } catch {
            infoError = error.localizedDescription
            LogManager.shared.log("[Statistics] Server info failed: \(error.localizedDescription)")
        }
        isLoadingInfo = false
    }

    @MainActor
    private func loadTagCloud() async {
        do {
            tagCloud = try await server.apiClient.fetchTagCloud()
            LogManager.shared.log("[Statistics] Tag cloud loaded count=\(tagCloud?.items.count ?? 0)")
        } catch {
            cloudError = error.localizedDescription
            LogManager.shared.log("[Statistics] Tag cloud failed: \(error.localizedDescription)")
        }
        isLoadingCloud = false
    }
}

private struct StatisticsWrappingLayout: Layout {
    enum Alignment {
        case center
        case trailing
    }

    let alignment: Alignment
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let rows = makeRows(width: width, subviews: subviews)
        let height = rows.enumerated().reduce(CGFloat.zero) { result, entry in
            result + entry.element.height + (entry.offset == rows.count - 1 ? 0 : verticalSpacing)
        }
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(width: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowX: CGFloat
            switch alignment {
            case .center:
                rowX = bounds.minX + max((bounds.width - row.width) / 2, 0)
            case .trailing:
                rowX = bounds.maxX - row.width
            }

            var x = rowX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func makeRows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = row.indices.isEmpty
                ? size.width
                : row.width + horizontalSpacing + size.width

            if !row.indices.isEmpty, proposedWidth > width {
                rows.append(row)
                row = Row()
            }

            if !row.indices.isEmpty { row.width += horizontalSpacing }
            row.indices.append(index)
            row.width += size.width
            row.height = max(row.height, size.height)
        }

        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
