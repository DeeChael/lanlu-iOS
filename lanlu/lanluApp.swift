import SwiftUI
import SwiftData

@main
struct lanluApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Server.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [modelConfiguration])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
