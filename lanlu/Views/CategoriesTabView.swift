import SwiftUI

@MainActor
private enum CategoriesTabMemoryCache {
    struct Snapshot {
        let filters: [APIClient.SmartFilterItem]
        let categories: [APIClient.CategoryItem]
        let selectedFilterId: Int?
        let selectedCategoryId: String?
        let items: [SearchResultItem]
        let hasMore: Bool
        let nextPage: Int
    }

    static var snapshots: [String: Snapshot] = [:]
}

struct CategoriesTabView: View {
    let server: Server

    @State private var filters: [APIClient.SmartFilterItem] = []
    @State private var categories: [APIClient.CategoryItem] = []
    @State private var selectedFilterId: Int?
    @State private var selectedCategoryId: String?
    @State private var items: [SearchResultItem] = []
    @State private var isLoadingInitial = true
    @State private var isLoadingItems = false
    @State private var hasMore = true
    @State private var nextPage = 1
    @State private var showSelection = false
    @State private var errorMessage: String?
    @State private var hasLoadedInitialData: Bool

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var selectedFilter: APIClient.SmartFilterItem? {
        filters.first { $0.id == selectedFilterId }
    }

    init(server: Server) {
        self.server = server
        if let snapshot = CategoriesTabMemoryCache.snapshots[server.baseURL] {
            _filters = State(initialValue: snapshot.filters)
            _categories = State(initialValue: snapshot.categories)
            _selectedFilterId = State(initialValue: snapshot.selectedFilterId)
            _selectedCategoryId = State(initialValue: snapshot.selectedCategoryId)
            _items = State(initialValue: snapshot.items)
            _isLoadingInitial = State(initialValue: false)
            _hasMore = State(initialValue: snapshot.hasMore)
            _nextPage = State(initialValue: snapshot.nextPage)
            _hasLoadedInitialData = State(initialValue: true)
        } else {
            _hasLoadedInitialData = State(initialValue: false)
        }
    }

    var body: some View {
        Group {
            if isLoadingInitial {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filters.isEmpty {
                ContentUnavailableView(
                    String(localized: "categories_no_smart_filters"),
                    systemImage: "square.grid.2x2"
                )
            } else if items.isEmpty && isLoadingItems {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView(
                    String(localized: "categories_no_results"),
                    systemImage: "books.vertical"
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items, id: \.displayId) { item in
                            ArchiveGridCell(archive: item, server: server)
                                .id("\(item.displayId)-\(item.progress ?? 0)")
                                .onAppear { loadMoreIfNeeded(item) }
                        }
                        if isLoadingItems {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(12)
                }
                .refreshable { await loadItems(reset: true) }
            }
        }
        .toolbar {
            if !filters.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSelection = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showSelection) {
            selectionSheet
                .presentationDetents([.large])
        }
        .navigationDestination(for: SearchResultItem.self) { item in
            ArchiveDetailView(archive: item, server: server)
        }
        .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            guard !hasLoadedInitialData else { return }
            await loadInitialData()
        }
        .onAppear {
            syncProgressFromCache()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .readerProgressDidChange)
        ) { notification in
            applyReaderProgressChange(notification)
        }
    }

    private var selectionSheet: some View {
        NavigationStack {
            List {
                Section(String(localized: "categories_smart_filters")) {
                    ForEach(filters) { filter in
                        Button {
                            selectFilter(filter)
                        } label: {
                            HStack {
                                Label(filterTitle(filter), systemImage: icon(for: filter.icon))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedFilterId == filter.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(String(localized: "categories_categories")) {
                    Button {
                        selectCategory(nil)
                    } label: {
                        HStack {
                            Text(String(localized: "home_filter_all"))
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedCategoryId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(categories, id: \.id) { category in
                        Button {
                            selectCategory(category.catid)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name).foregroundStyle(.primary)
                                    if let description = category.description,
                                       !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedCategoryId == category.catid {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(String(localized: "categories_select"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSelection = false } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadInitialData() async {
        isLoadingInitial = true
        do {
            async let loadedFilters = server.apiClient.fetchSmartFilters()
            async let loadedCategories = server.apiClient.fetchCategories()
            let (filterResult, categoryResult) = try await (loadedFilters, loadedCategories)
            filters = filterResult.sorted {
                ($0.sortOrderNumber ?? Int.max) < ($1.sortOrderNumber ?? Int.max)
            }
            categories = categoryResult
            selectedFilterId = filters.first?.id
            if !filters.isEmpty {
                await loadItems(reset: true)
            }
            hasLoadedInitialData = true
            saveSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[CategoriesTab] Initial load failed: \(error.localizedDescription)")
        }
        isLoadingInitial = false
    }

    private func selectFilter(_ filter: APIClient.SmartFilterItem) {
        guard selectedFilterId != filter.id else { return }
        selectedFilterId = filter.id
        showSelection = false
        saveSnapshot()
        Task { await loadItems(reset: true) }
    }

    private func selectCategory(_ categoryId: String?) {
        guard selectedCategoryId != categoryId else { return }
        selectedCategoryId = categoryId
        showSelection = false
        saveSnapshot()
        Task { await loadItems(reset: true) }
    }

    private func loadItems(reset: Bool) async {
        guard !isLoadingItems, let filter = selectedFilter else { return }
        isLoadingItems = true
        if reset {
            items = []
            nextPage = 1
            hasMore = true
        }

        do {
            let result = try await server.apiClient.search(
                untaggedOnly: filter.untaggedOnly ?? false,
                newonly: filter.newOnly ?? false,
                groupbyTanks: true,
                filter: filter.query,
                category_id: selectedCategoryId,
                sortby: filter.sortBy ?? "",
                order: filter.sortOrder ?? "desc",
                dateFrom: relativeDateString(days: filter.dateFrom),
                dateTo: relativeDateString(days: filter.dateTo),
                page: nextPage,
                pageSize: pageSize
            )
            let newItems = result.data ?? []
            for item in newItems where !items.contains(where: { $0.displayId == item.displayId }) {
                items.append(item)
            }
            nextPage += 1
            hasMore = newItems.count >= pageSize
            saveSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            hasMore = false
            LogManager.shared.log("[CategoriesTab] Items load failed: \(error.localizedDescription)")
        }
        isLoadingItems = false
    }

    private func loadMoreIfNeeded(_ item: SearchResultItem) {
        guard hasMore,
              !isLoadingItems,
              let index = items.firstIndex(where: { $0.displayId == item.displayId }),
              index >= items.count - 5 else { return }
        Task { await loadItems(reset: false) }
    }

    private func relativeDateString(days: Int?) -> String? {
        guard let days else { return nil }
        guard let date = Calendar.current.date(
            byAdding: .day,
            value: days,
            to: Calendar.current.startOfDay(for: Date())
        ) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func filterTitle(_ filter: APIClient.SmartFilterItem) -> String {
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        if !isChinese,
           let translated = filter.translations?["en"]?.text,
           !translated.isEmpty {
            return translated
        }
        return filter.name
    }

    private func icon(for value: String?) -> String {
        switch value {
        case "BookOpen": "book"
        case "Tag": "tag"
        case "Calendar": "calendar"
        case "Search": "magnifyingglass"
        case "Clock": "clock"
        case "Star": "star"
        default: "line.3.horizontal.decrease"
        }
    }

    private func syncProgressFromCache() {
        for index in items.indices {
            guard let arcid = items[index].arcid,
                  let cached = CacheManager.shared.getArchiveMetadata(arcid: arcid),
                  let metadata = try? JSONDecoder().decode(
                    APIClient.ArchiveMetadata.self,
                    from: cached
                  ) else { continue }
            items[index].progress = metadata.progress
        }
        saveSnapshot()
    }

    private func applyReaderProgressChange(_ notification: Notification) {
        guard notification.userInfo?["serverId"] as? String == server.baseURL,
              let arcid = notification.userInfo?["arcid"] as? String,
              let page = notification.userInfo?["page"] as? Int,
              let index = items.firstIndex(where: { $0.arcid == arcid }) else { return }
        items[index].progress = page
        saveSnapshot()
    }

    private func saveSnapshot() {
        guard hasLoadedInitialData || !filters.isEmpty else { return }
        CategoriesTabMemoryCache.snapshots[server.baseURL] = .init(
            filters: filters,
            categories: categories,
            selectedFilterId: selectedFilterId,
            selectedCategoryId: selectedCategoryId,
            items: items,
            hasMore: hasMore,
            nextPage: nextPage
        )
    }
}
