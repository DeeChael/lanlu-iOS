import SwiftUI

struct SearchView: View {
    let server: Server

    @State private var suggestions: [AutocompleteSuggestion] = []
    @State private var results: [SearchResultItem] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var hasSearched = false
    @State private var query = ""
    @State private var currentQuery = ""
    @State private var nextStart = 0

    @State private var sortField = "created_at"
    @State private var sortOrder = "desc"
    @State private var dateEnabled = false
    @State private var dateFrom = Date()
    @State private var dateTo = Date()
    @State private var untaggedOnly = false
    @State private var favoriteOnly = false
    @State private var showFilter = false

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let historyKey = "search_history"

    private var recentSearches: [String] {
        get { UserDefaults.standard.stringArray(forKey: historyKey) ?? [] }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: historyKey) }
    }

    var body: some View {
        Group {
            if hasSearched {
                resultsView
            } else if query.isEmpty {
                historyView
            } else {
                suggestionsView
            }
        }
        .searchable(text: $query, prompt: "search_prompt")
        .onSubmit(of: .search) {
            performSearch()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    if !query.isEmpty {
                        Button(String(localized: "search_go")) {
                            performSearch()
                        }
                        .fontWeight(.semibold)
                    }
                    Button { showFilter = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            FilterSheetView(
                sortField: $sortField, sortOrder: $sortOrder,
                dateEnabled: $dateEnabled,
                dateFrom: $dateFrom, dateTo: $dateTo,
                untaggedOnly: $untaggedOnly, favoriteOnly: $favoriteOnly,
                onReset: resetFilters
            )
        }
        .onChange(of: query) { _, newValue in
            hasSearched = false
            if !newValue.isEmpty { Task { await loadSuggestions() } }
        }
        .navigationTitle(String(localized: "tab_search"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var historyView: some View {
        let history = recentSearches
        return Group {
            if history.isEmpty {
                ContentUnavailableView("search_history_empty", systemImage: "clock.arrow.circlepath", description: Text("search_history_empty_desc"))
            } else {
                List {
                    Section(String(localized: "search_history")) {
                        ForEach(history, id: \.self) { term in
                            Button {
                                query = term
                                DispatchQueue.main.async { performSearch() }
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath").foregroundColor(.secondary)
                                    Text(term).foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var suggestionsView: some View {
        List {
            if suggestions.isEmpty {
                Section {
                    Text(String(localized: "search_no_suggestions")).foregroundColor(.secondary)
                }
            } else {
                Section(String(localized: "search_suggestions")) {
                    ForEach(suggestions, id: \.value) { sug in
                        Button {
                            query = sug.label
                            DispatchQueue.main.async { performSearch() }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sug.label).foregroundColor(.primary)
                                if sug.value != sug.label {
                                    Text(sug.value).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var resultsView: some View {
        ZStack {
            if results.isEmpty && isLoading {
                ProgressView()
            } else if results.isEmpty {
                ContentUnavailableView("search_no_results", systemImage: "magnifyingglass", description: Text("search_no_results_desc"))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(results, id: \.arcid) { item in
                            ArchiveGridCell(archive: item, server: server)
                                .onAppear { loadMoreIfNeeded(item) }
                        }
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func saveHistory(_ term: String) {
        var history = recentSearches
        if !history.contains(term) {
            history.insert(term, at: 0)
            if history.count > 20 { history = Array(history.prefix(20)) }
            recentSearches = history
        }
    }

    private func performSearch() {
        guard !query.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        hasSearched = true
        suggestions = []
        results = []
        hasMore = true
        currentQuery = query
        nextStart = 0
        saveHistory(query)
        Task { await doSearch() }
    }

    private func doSearch() async {
        guard !isLoading else { return }
        isLoading = true
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        do {
            let result = try await server.apiClient.search(
                favoriteOnly: favoriteOnly, untaggedOnly: untaggedOnly,
                filter: currentQuery.isEmpty ? nil : currentQuery,
                sortby: sortField, order: sortOrder,
                dateFrom: dateEnabled ? df.string(from: dateFrom) : nil,
                dateTo: dateEnabled ? df.string(from: dateTo) : nil,
                start: nextStart, count: pageSize
            )
            let items = result.data ?? []
            for item in items {
                if !results.contains(where: { $0.arcid == item.arcid }) {
                    results.append(item)
                }
            }
            nextStart = results.count
            hasMore = items.count == pageSize
        } catch { hasMore = false }
        isLoading = false
    }

    private func loadSuggestions() async {
        guard !query.isEmpty else { suggestions = []; return }
        do { suggestions = try await server.apiClient.autocomplete(query: query) }
        catch { suggestions = [] }
    }

    private func loadMoreIfNeeded(_ item: SearchResultItem) {
        guard hasMore, !isLoading,
              let index = results.firstIndex(where: { $0.arcid == item.arcid }),
              index >= results.count - 5 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        do {
            let result = try await server.apiClient.search(
                favoriteOnly: favoriteOnly, untaggedOnly: untaggedOnly,
                filter: currentQuery.isEmpty ? nil : currentQuery,
                sortby: sortField, order: sortOrder,
                dateFrom: dateEnabled ? df.string(from: dateFrom) : nil,
                dateTo: dateEnabled ? df.string(from: dateTo) : nil,
                start: nextStart, count: pageSize
            )
            let items = result.data ?? []
            for item in items {
                if !results.contains(where: { $0.arcid == item.arcid }) {
                    results.append(item)
                }
            }
            nextStart = results.count
            hasMore = items.count == pageSize
        } catch { hasMore = false }
        isLoading = false
    }

    private func resetFilters() {
        sortField = "created_at"; sortOrder = "desc"
        dateEnabled = false; dateFrom = Date(); dateTo = Date()
        untaggedOnly = false; favoriteOnly = false
    }
}
