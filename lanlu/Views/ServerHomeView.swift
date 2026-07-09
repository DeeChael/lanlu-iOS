import SwiftUI
import SwiftData

struct ServerHomeView: View {
    let server: Server
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    @State private var searching = ""

    private var tabTitle: String {
        switch selectedTab {
        case 0: String(localized: "tab_home")
        case 1: String(localized: "tab_favorites")
        case 2: String(localized: "tab_settings")
        case 3: String(localized: "tab_search")
        default: ""
        }
    }

    var body: some View {
        TabView {
            Tab(String(localized: "tab_home"), systemImage: "house.fill") {
                HomeTabView()
            }
            Tab(String(localized: "tab_favorites"), systemImage: "heart.fill") {
                FavoritesTabView()
            }
            Tab(String(localized: "tab_settings"), systemImage: "gearshape.fill") {
                SettingsTabView(server: server)
            }
            Tab(String(localized: "tab_search"), systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    Color.clear
                    // todo: search view
                }
            }
        }
        .searchable(text: $searching, prompt: "search_prompt")
        .tabViewSearchActivation(.searchTabSelection)
        .navigationTitle(tabTitle)
        .navigationBarBackButtonHidden(true)
        .task {
            server.lastUsedAt = Date()
            try? modelContext.save()
            UserDefaults.standard.set(server.baseURL, forKey: "last_server_url")
            LogManager.shared.log("Entered server: \(server.name) (\(server.baseURL))")
        }
    }
}
