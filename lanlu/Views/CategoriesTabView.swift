import SwiftUI

struct CategoriesTabView: View {
    let server: Server

    @State private var filters: [APIClient.SmartFilterItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if filters.isEmpty {
                ContentUnavailableView(
                    String(localized: "categories_no_smart_filters"),
                    systemImage: "square.grid.2x2"
                )
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadFilters()
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadFilters() async {
        isLoading = true
        do {
            filters = try await server.apiClient.fetchSmartFilters()
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[CategoriesTab] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}
