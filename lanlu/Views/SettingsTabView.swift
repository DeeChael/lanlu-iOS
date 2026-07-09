import SwiftUI
import SwiftData

struct SettingsTabView: View {
    let server: Server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var user: UserData?
    @State private var avatarData: Data?
    @State private var isLoadingUser = true

    private var client: APIClient { server.apiClient }

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
        }
        .navigationTitle(String(localized: "tab_settings"))
        .task {
            await loadUserInfo()
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
