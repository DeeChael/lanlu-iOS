import SwiftUI
import SwiftData

struct ServerHomeView: View {
    let server: Server
    @Environment(\.modelContext) private var modelContext
    @State private var searching = ""

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
                    FavoritesTabView()
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
            server.lastUsedAt = Date()
            try? modelContext.save()
            UserDefaults.standard.set(server.baseURL, forKey: "last_server_url")
            LogManager.shared.log("Entered server: \(server.name) (\(server.baseURL))")
        }
    }
}
