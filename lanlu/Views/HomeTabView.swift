import SwiftUI

struct HomeTabView: View {
    let server: Server

    @State private var recommendations: [SearchResultItem] = []
    @State private var categories: [APIClient.CategoryItem] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var selectedCategoryId: Int? = nil
    @State private var showFilter = false
    @State private var scrollToTop = false
    @State private var hasFetchedCategories = false

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ZStack {
            if recommendations.isEmpty && isLoading {
                ProgressView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(recommendations, id: \.displayId) { item in
                                ArchiveGridCell(archive: item, server: server)
                                    .onAppear { loadMoreIfNeeded(item) }
                            }
                            if isLoading {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            }
                        }
                        .padding(12)
                        .id("top")
                    }
                    .onChange(of: scrollToTop) { _, _ in
                        withAnimation { proxy.scrollTo("top", anchor: .top) }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showFilter = true } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            NavigationStack {
                List {
                    Button {
                        selectedCategoryId = nil
                        showFilter = false
                        DispatchQueue.main.async { refresh() }
                        scrollToTop.toggle()
                    } label: {
                        HStack {
                            Text(String(localized: "home_filter_all")).foregroundColor(.primary)
                            Spacer()
                            if selectedCategoryId == nil {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }

                    ForEach(categories, id: \.id) { cat in
                        Button {
                            selectedCategoryId = cat.id
                            showFilter = false
                            DispatchQueue.main.async { refresh() }
                            scrollToTop.toggle()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.name).foregroundColor(.primary)
                                    if let desc = cat.description, !desc.isEmpty {
                                        Text(desc).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedCategoryId == cat.id {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(String(localized: "home_filter"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { showFilter = false } label: {
                            Image(systemName: "xmark").fontWeight(.semibold)
                        }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .navigationDestination(for: SearchResultItem.self) { item in
            ArchiveDetailView(archive: item, server: server)
        }
        .task {
            await loadInitial()
        }
    }

    private func loadInitial() async {
        print("[Home] Loading initial data")
        do {
            let cats = try await server.apiClient.fetchCategories()
            categories = cats
            hasFetchedCategories = true
            print("[Home] Categories loaded: \(cats.count)")
        } catch {
            print("[Home] Categories error: \(error)")
        }

        isLoading = true
        do {
            let items = try await server.apiClient.fetchRecommendations(count: pageSize, categoryId: selectedCategoryId)
            print("[Home] Recommendations loaded: \(items.count)")
            for item in items {
                if !recommendations.contains(where: { $0.displayId == item.displayId }) {
                    recommendations.append(item)
                }
            }
            hasMore = items.count == pageSize
        } catch {
            print("[Home] Recommendations error: \(error)")
        }
        isLoading = false
    }

    private func refresh() {
        print("[Home] Refreshing with categoryId: \(selectedCategoryId ?? 0)")
        recommendations = []
        hasMore = true
        isLoading = false
        Task { await loadRecommendations(reset: true) }
    }

    private func loadRecommendations(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset { recommendations = [] }

        do {
            let items = try await server.apiClient.fetchRecommendations(count: pageSize, categoryId: selectedCategoryId)
            print("[Home] Got \(items.count) items")
            var newCount = 0
            for item in items {
                if !recommendations.contains(where: { $0.displayId == item.displayId }) {
                    recommendations.append(item)
                    newCount += 1
                }
            }
            print("[Home] Added \(newCount) new, total \(recommendations.count)")
            hasMore = items.count == pageSize
        } catch {
            print("[Home] Error: \(error)")
            hasMore = false
        }
        isLoading = false
    }

    private func loadMoreIfNeeded(_ item: SearchResultItem) {
        guard hasMore, !isLoading,
              let index = recommendations.firstIndex(where: { $0.displayId == item.displayId }),
              index >= recommendations.count - 5 else { return }
        print("[Home] Loading more...")
        Task { await loadRecommendations(reset: false) }
    }
}
