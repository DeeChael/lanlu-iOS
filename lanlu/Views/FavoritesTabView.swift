import SwiftUI

struct FavoritesTabView: View {
    var body: some View {
        ContentUnavailableView(
            "favorites_placeholder",
            systemImage: "heart.fill",
            description: Text("favorites_placeholder_desc")
        )
    }
}
