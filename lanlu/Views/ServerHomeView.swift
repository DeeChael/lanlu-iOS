import SwiftUI
import SwiftData

struct ServerHomeView: View {
    let server: Server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var searching = ""
    @State private var showConnectionError = false
    @State private var connectionErrorText = ""

    var body: some View {
        TabView {
            Tab(String(localized: "tab_home"), systemImage: "house.fill") {
                NavigationStack {
                    HomeTabView()
                        .navigationTitle(String(localized: "tab_home"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_favorites"), systemImage: "heart.fill") {
                NavigationStack {
                    FavoritesTabView(server: server)
                        .navigationTitle(String(localized: "tab_favorites"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_history"), systemImage: "clock.fill") {
                NavigationStack {
                    HistoryTabView()
                        .navigationTitle(String(localized: "tab_history"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_settings"), systemImage: "gearshape.fill") {
                NavigationStack {
                    SettingsTabView(server: server)
                        .navigationTitle(String(localized: "tab_settings"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_search"), systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    Color.clear
                    // todo: search view
                }
            }
        }
        .searchable(text: $searching, prompt: "search_prompt")
        .navigationBarBackButtonHidden(true)
        .task {
            await checkServer()
        }
        .alert(String(localized: "connection_lost"), isPresented: $showConnectionError) {
            Button(String(localized: "ok")) {
                dismiss()
            }
        } message: {
            Text(connectionErrorText)
        }
    }

    private func checkServer() async {
        server.lastUsedAt = Date()
        try? modelContext.save()
        UserDefaults.standard.set(server.baseURL, forKey: "last_server_url")
        LogManager.shared.log("Entered server: \(server.name) (\(server.baseURL))")

        do {
            _ = try await NetworkService.shared.testConnection(baseURL: server.baseURL)
        } catch {
            connectionErrorText = error.localizedDescription
            showConnectionError = true
        }
    }
}
