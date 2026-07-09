import SwiftUI
import SwiftData

struct ServerHomeView: View {
    
    let server: Server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selected = 0
    @State private var showConnectionError = false
    @State private var connectionErrorText = ""
    @State private var showFilter = false
    @State private var searching = false

    @State private var sortField = "created_at"
    @State private var sortOrder = "desc"
    @State private var dateEnabled = false
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var untaggedOnly = false
    @State private var favoriteOnly = false

    var body: some View {
        TabView(selection: $selected) {
            Tab(String(localized: "tab_home"), systemImage: "house.fill", value: 0) {
                NavigationStack {
                    HomeTabView()
                        .navigationTitle(String(localized: "tab_home"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_favorites"), systemImage: "heart.fill", value: 1) {
                NavigationStack {
                    FavoritesTabView(server: server)
                        .navigationTitle(String(localized: "tab_favorites"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_history"), systemImage: "clock.fill", value: 2) {
                NavigationStack {
                    HistoryTabView(server: server)
                        .navigationTitle(String(localized: "tab_history"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_settings"), systemImage: "gearshape.fill", value: 3) {
                NavigationStack {
                    SettingsTabView(server: server)
                        .navigationTitle(String(localized: "tab_settings"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }

            Tab(String(localized: "tab_search"), systemImage: "magnifyingglass", value: 4, role: .search) {
                NavigationStack {
                    SearchView(
                        server: server, showFilter: $showFilter, searching: $searching,
                        sortField: $sortField, sortOrder: $sortOrder,
                        dateEnabled: $dateEnabled, dateFrom: $dateFrom, dateTo: $dateTo,
                        untaggedOnly: $untaggedOnly, favoriteOnly: $favoriteOnly
                    )
                    .navigationTitle(String(localized: "tab_search"))
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .tabViewBottomAccessory(isEnabled: selected == 4) {
            Button { showFilter = true } label: {
                HStack {
                    Label(String(localized: "search_filter"), systemImage: "slider.horizontal.3")
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showFilter) {
            FilterSheetView(
                sortField: $sortField, sortOrder: $sortOrder,
                dateEnabled: $dateEnabled,
                dateFrom: $dateFrom, dateTo: $dateTo,
                untaggedOnly: $untaggedOnly, favoriteOnly: $favoriteOnly,
                onReset: {
                    sortField = "created_at"; sortOrder = "desc"
                    dateEnabled = false; dateFrom = Date(); dateTo = Date()
                    untaggedOnly = false; favoriteOnly = false
                }
            )
        }
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
