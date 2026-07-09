import SwiftUI

struct HistoryTabView: View {
    var body: some View {
        ContentUnavailableView(
            "history_placeholder",
            systemImage: "clock.fill",
            description: Text("history_placeholder_desc")
        )
    }
}
