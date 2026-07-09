import SwiftUI
import SwiftData

@main
struct lanluApp: App {
    @AppStorage("theme_mode") private var themeMode = "system"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Server.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [modelConfiguration])
    }()

    private var colorScheme: ColorScheme? {
        switch themeMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
