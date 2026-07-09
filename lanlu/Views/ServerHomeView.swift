import SwiftUI

struct ServerHomeView: View {
    let server: Server

    var body: some View {
        TabView {
            HomeTabView()
                .tabItem {
                    Label(String(localized: "tab_home"), systemImage: "house.fill")
                }

            FavoritesTabView()
                .tabItem {
                    Label(String(localized: "tab_favorites"), systemImage: "heart.fill")
                }

            SettingsTabView(server: server)
                .tabItem {
                    Label(String(localized: "tab_settings"), systemImage: "gearshape.fill")
                }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview {
    NavigationStack {
        Text("Preview")
    }
}
