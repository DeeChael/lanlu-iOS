import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Server.lastUsedAt, order: .reverse) private var servers: [Server]
    @State private var showAddServer = false
    @State private var showSettings = false
    @State private var serverToEdit: Server?
    @State private var activeServer: Server?

    var body: some View {
        NavigationStack {
            Group {
                if servers.isEmpty {
                    emptyState
                } else {
                    serverList
                }
            }
            .navigationTitle(String(localized: "app_name"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        serverToEdit = nil
                        showAddServer = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView(existingServer: serverToEdit)
            }
            .sheet(isPresented: $showSettings) {
                ClientSettingsSheetView()
                    .presentationDetents([.large])
            }
            .onChange(of: showAddServer) { _, isShowing in
                if !isShowing { serverToEdit = nil }
            }
            .fullScreenCover(item: $activeServer) { server in
                ServerHomeView(server: server)
            }
            .task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                navigateToLastServer()
            }
        }
    }

    private func navigateToLastServer() {
        guard let url = UserDefaults.standard.string(forKey: "last_server_url"),
              let server = servers.first(where: { $0.baseURL == url }) else {
            LogManager.shared.log("No last server to navigate to")
            return
        }
        LogManager.shared.log("Auto-navigating to \(server.name) (\(url))")
        activeServer = server
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "no_servers_yet"), systemImage: "server.rack")
        } description: {
            Text(String(localized: "no_servers_desc"))
        } actions: {
            Button(String(localized: "add_server")) {
                serverToEdit = nil
                showAddServer = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var serverList: some View {
        List {
            ForEach(servers) { server in
                Button {
                    activeServer = server
                } label: {
                    ServerRow(server: server)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(server)
                    } label: {
                        Image(systemName: "trash.fill")
                    }

                    Button {
                        serverToEdit = server
                        showAddServer = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(servers[index])
        }
    }
}

func lastUsedFormatted(_ date: Date) -> String {
    let now = Date()
    let interval = now.timeIntervalSince(date)

    if interval < 60 {
        return String(localized: "just_now")
    }

    let calendar = Calendar.current
    if interval < 7 * 24 * 60 * 60 {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    let isThisYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = isThisYear ? "M/d" : "y/M/d"
    return dateFormatter.string(from: date)
}

struct ServerRow: View {
    let server: Server

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(server.name)
                .font(.headline)

            Text(server.baseURL)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                if let lastUsed = server.lastUsedAt {
                    Text(String(localized: "last_used"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(lastUsedFormatted(lastUsed))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text(String(localized: "never_used"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
