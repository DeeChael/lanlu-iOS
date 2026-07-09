import SwiftUI

struct HomeTabView: View {
    var body: some View {
        ContentUnavailableView(
            "home_placeholder",
            systemImage: "house.fill",
            description: Text("home_placeholder_desc")
        )
    }
}
