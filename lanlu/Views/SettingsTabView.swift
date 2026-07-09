import SwiftUI
import SwiftData
import Charts

struct SettingsTabView: View {
    let server: Server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var user: UserData?
    @State private var avatarData: Data?
    @State private var isLoadingUser = true
    @State private var stats: UserStatsData?
    @State private var trend: UserTrendData?
    @State private var statsError: String?
    @State private var trendError: String?

    private var client: APIClient { server.apiClient }
    private let gridCols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let avatarData, let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if isLoadingUser {
                            ProgressView()
                        } else {
                            Text(user?.username ?? server.cachedUsername ?? "---")
                                .font(.headline)
                        }

                        Text(server.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(server.baseURL)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }

            Section(String(localized: "stats_title")) {
                if let statsError {
                    Text(statsError)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                LazyVGrid(columns: gridCols, spacing: 12) {
                    StatCell(
                        icon: "heart.fill",
                        label: String(localized: "stat_favorites"),
                        value: "\(stats?.favoriteCount ?? 0)"
                    )
                    StatCell(
                        icon: "checkmark.circle.fill",
                        label: String(localized: "stat_read_archives"),
                        value: "\(stats?.readCount ?? 0)"
                    )
                    StatCell(
                        icon: "book.pages.fill",
                        label: String(localized: "stat_pages_read"),
                        value: "\(stats?.totalPagesRead ?? 0)"
                    )
                    StatCell(
                        icon: "archivebox.fill",
                        label: String(localized: "stat_total_archives"),
                        value: "\(stats?.totalArchives ?? 0)"
                    )
                }

                if let trend, !trend.trend.isEmpty {
                    Chart(trend.trend, id: \.date) { point in
                        LineMark(
                            x: .value("date", point.date),
                            y: .value("count", point.count)
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 200)
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(String(localized: "trend_most_active")) {
                            Text(trend.mostActiveDate ?? "---")
                        }
                        LabeledContent(String(localized: "trend_active_days")) {
                            Text("\(trend.activeDays ?? 0)")
                        }
                        LabeledContent(String(localized: "trend_max_count")) {
                            Text("\(trend.maxCount ?? 0)")
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }

                if let trendError {
                    Text(trendError)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(String(localized: "tab_settings"))
        .task {
            await loadUserInfo()
            async let s = loadStats()
            async let t = loadTrend()
            _ = await (s, t)
        }
    }

    private func loadUserInfo() async {
        if let cached = server.cachedUsername {
            user = UserData(id: 0, username: cached, isAdmin: false, avatarAssetId: server.cachedAvatarAssetId)
            if let assetId = server.cachedAvatarAssetId {
                avatarData = try? await loadAvatar(assetId: assetId)
            }
            isLoadingUser = false
            return
        }

        isLoadingUser = true
        do {
            let userData = try await client.verifyToken()
            user = userData
            server.cachedUsername = userData.username
            server.cachedAvatarAssetId = userData.avatarAssetId
            try? modelContext.save()

            if let assetId = userData.avatarAssetId {
                avatarData = try? await loadAvatar(assetId: assetId)
            }
        } catch {
            user = nil
        }
        isLoadingUser = false
    }

    private func loadStats() async {
        do {
            stats = try await client.fetchStats()
            statsError = nil
        } catch {
            statsError = error.localizedDescription
        }
    }

    private func loadTrend() async {
        do {
            let result = try await client.fetchTrend()
            if !result.trend.isEmpty {
                trend = result
                trendError = nil
            } else {
                trendError = String(localized: "trend_empty")
            }
        } catch {
            trendError = error.localizedDescription
        }
    }

    private func loadAvatar(assetId: Int) async throws -> Data {
        var urlString = server.baseURL
        if !urlString.contains("://") {
            urlString = "https://" + urlString
        }
        guard let url = URL(string: urlString)?.appendingPathComponent("api/assets/\(assetId)") else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = server.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.networkError(String(localized: "connection_failed"))
        }
        return data
    }
}

struct StatCell: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
