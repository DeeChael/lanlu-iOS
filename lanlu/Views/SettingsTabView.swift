import SwiftUI
import SwiftData
import Charts

struct SettingsTabView: View {
    let server: Server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("theme_mode") private var themeMode = "system"
    @AppStorage("language") private var language = "system"

    @State private var user: UserData?
    @State private var avatarData: Data?
    @State private var isLoadingUser = true
    @State private var stats: UserStatsData?
    @State private var trend: UserTrendData?
    @State private var statsError: String?
    @State private var trendError: String?

    @State private var showLanguagePicker = false
    @State private var showDiagnostics = false
    @State private var showClearCacheAlert = false
    @State private var cacheInfo = ""
    @State private var showRestartAlert = false

    private var client: APIClient { server.apiClient }
    private let gridCols = [GridItem(.flexible()), GridItem(.flexible())]

    private var languageLabel: String {
        switch language {
        case "en": "English"
        case "zh-Hans": "简体中文"
        case "zh-Hant": "繁體中文"
        default: String(localized: "lang_system")
        }
    }

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
                            HStack(spacing: 6) {
                                Text(user?.username ?? server.cachedUsername ?? "---")
                                    .font(.headline)
                                if user?.isAdmin == true {
                                    Text("badge_admin")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
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
                        UserDefaults.standard.removeObject(forKey: "last_server_url")
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

                LazyVGrid(columns: gridCols, spacing: 4) {
                    StatCell(icon: "heart.fill", label: String(localized: "stat_favorites"), value: "\(stats?.favoriteCount ?? 0)")
                    StatCell(icon: "checkmark.circle.fill", label: String(localized: "stat_read_archives"), value: "\(stats?.readCount ?? 0)")
                    StatCell(icon: "book.pages.fill", label: String(localized: "stat_pages_read"), value: "\(stats?.totalPagesRead ?? 0)")
                    StatCell(icon: "archivebox.fill", label: String(localized: "stat_total_archives"), value: "\(stats?.totalArchives ?? 0)")
                }

                if let trend, !trend.trend.isEmpty {
                    let trendDates = trend.trend.compactMap(\.dateValue)
                    Chart(trend.trend, id: \.date) { point in
                        if let date = point.dateValue {
                            LineMark(x: .value("date", date), y: .value("count", point.count))
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: trendDates) { value in
                            if let date = value.as(Date.self) {
                                AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                            }
                        }
                    }
                    .frame(height: 200)
                    .padding(.vertical, 4)
                }

                if let trendError {
                    Text(trendError)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section(String(localized: "client_settings")) {
                HStack {
                    Label(String(localized: "setting_theme"), systemImage: "paintpalette.fill")
                    Spacer()
                    NativeSegmentedControl(
                        selection: $themeMode,
                        items: [
                            ("circle.righthalf.fill", nil, "system"),
                            ("sun.max.fill", nil, "light"),
                            ("moon.fill", nil, "dark"),
                        ]
                    )
                    .frame(width: 140)
                }

                Button {
                    showLanguagePicker = true
                } label: {
                    HStack {
                        Label(String(localized: "setting_language"), systemImage: "globe")
                        Spacer()
                        Text(languageLabel)
                            .foregroundColor(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showLanguagePicker) {
                    LanguagePickerView(selected: $language)
                }

                Button {
                    showDiagnostics = true
                } label: {
                    HStack {
                        Label(String(localized: "setting_diagnostics"), systemImage: "ant.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showDiagnostics) {
                    DiagnosticsView()
                }

                Button(role: .destructive) {
                    cacheInfo = String(format: String(localized: "clear_cache_detail"), CacheManager.shared.metadataCacheCount, CacheManager.shared.diskCacheCount)
                    showClearCacheAlert = true
                } label: {
                    HStack {
                        Label(String(localized: "setting_clear_cache"), systemImage: "trash.fill")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .tint(.red)
                .alert(String(localized: "clear_cache_title"), isPresented: $showClearCacheAlert) {
                    Button(String(localized: "cancel"), role: .cancel) {}
                    Button(String(localized: "confirm"), role: .destructive) { clearCache() }
                } message: {
                    Text(cacheInfo)
                }
            }

            Section(String(localized: "server_settings")) {
                Button {} label: {
                    HStack {
                        Label(String(localized: "ss_account_security"), systemImage: "shield.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if user?.isAdmin == true {
                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_category"), systemImage: "folder.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_tags"), systemImage: "tag.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_smart_filters"), systemImage: "line.3.horizontal.decrease")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_user_management"), systemImage: "person.2.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_system_settings"), systemImage: "server.rack")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_background_tasks"), systemImage: "calendar.badge.clock")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_scheduled_tasks"), systemImage: "clock.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_plugin_management"), systemImage: "puzzlepiece.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {} label: {
                        HStack {
                            Label(String(localized: "ss_statistics"), systemImage: "chart.bar.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            await loadUserInfo()
            async let s = loadStats()
            async let t = loadTrend()
            _ = await (s, t)
        }
        .onChange(of: language) { _, newValue in
            if newValue != "system" {
                UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
            showRestartAlert = true
        }
        .alert(String(localized: "restart_title"), isPresented: $showRestartAlert) {
            Button(String(localized: "restart_now")) {
                exit(0)
            }
            Button(String(localized: "later"), role: .cancel) {}
        } message: {
            Text(String(localized: "restart_message"))
        }
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        CacheManager.shared.clearAll()
        LogManager.shared.log("Cache cleared (URLCache + ArchiveCache)")
    }

    private func loadUserInfo() async {
        if let cached = server.cachedUsername {
            user = UserData(id: 0, username: cached, isAdmin: false, avatarAssetId: server.cachedAvatarAssetId)
            if let assetId = server.cachedAvatarAssetId {
                avatarData = try? await loadAvatar(assetId: assetId)
            }
        }

        isLoadingUser = !(server.cachedUsername != nil)
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
            if server.cachedUsername == nil { user = nil }
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
            let result = try await client.fetchTrend(days: 7)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxHeight: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
