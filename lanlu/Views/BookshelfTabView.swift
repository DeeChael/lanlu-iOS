import SwiftUI

struct BookshelfTabView: View {
    private enum Selection: String, CaseIterable, Identifiable {
        case favorites
        case history

        var id: String { rawValue }
    }

    let server: Server
    @State private var selection: Selection = .favorites

    var body: some View {
        Group {
            switch selection {
            case .favorites:
                FavoritesTabView(server: server)
            case .history:
                HistoryTabView(server: server)
            }
        }
        .safeAreaBar(edge: .top) {
            Picker("", selection: $selection) {
                Text(String(localized: "tab_favorites"))
                    .tag(Selection.favorites)
                Text(String(localized: "tab_history"))
                    .tag(Selection.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}
