import SwiftUI

struct ServerHomeView: View {
    let server: Server
    @State private var selectedTab = 0

    private var tabTitle: String {
        switch selectedTab {
        case 0: String(localized: "tab_home")
        case 1: String(localized: "tab_favorites")
        case 2: String(localized: "tab_settings")
        default: ""
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView()
                .tabItem {
                    Label(String(localized: "tab_home"), systemImage: "house.fill")
                }
                .tag(0)

            FavoritesTabView()
                .tabItem {
                    Label(String(localized: "tab_favorites"), systemImage: "heart.fill")
                }
                .tag(1)

            SettingsTabView(server: server)
                .tabItem {
                    Label(String(localized: "tab_settings"), systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .navigationTitle(tabTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        Text("Preview")
    }
}
