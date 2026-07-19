import SwiftUI

struct SearchView: View {
    
    let server: Server
    @Binding var showFilter: Bool
    @Binding var searching: Bool
    @Binding var sortField: String
    @Binding var sortOrder: String
    @Binding var dateEnabled: Bool
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var newOnly: Bool
    @Binding var untaggedOnly: Bool
    @Binding var favoriteOnly: Bool
    @State private var suggestions: [AutocompleteSuggestion] = []
    @State private var cachedSuggestions: [AutocompleteSuggestion] = []
    @State private var results: [SearchResultItem] = []
    @State private var isLoading = false
    @FocusState private var searchFocused: Bool
    @State private var hasMore = true
    @State private var hasSearched = false
    @State private var query = ""
    @State private var currentQuery = ""
    @State private var currentTags: String? = nil
    @State private var nextStart = 0
    @State private var tags: [(value: String, label: String, display: String)] = []
    @State private var isAddingTag = false
    @State private var showClearHistoryAlert = false

    private let pageSize = 20
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let historyKey = "search_history"

    private struct HistoryEntry: Codable, Hashable {
        let query: String
        let tags: [String]
    }

    private var recentSearches: [HistoryEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: historyKey) else { return [] }
            return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
        }
        nonmutating set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if hasSearched {
                    resultsView
                } else if query.isEmpty && tags.isEmpty {
                    historyView
                } else {
                    suggestionsView
                }
            }
        }
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) {
            if !tags.isEmpty {
                TagFlowView(tags: $tags, onTagRemoved: { onTagRemoved() })
                    .padding(.horizontal, 16)
                    .padding(.bottom, searchFocused ? 60 : 4)
            }
        }
        .searchable(text: $query, isPresented: $searching, prompt: "search_prompt")
        .searchFocused($searchFocused)
        .onSubmit(of: .search) {
            performSearch()
        }
        .navigationDestination(for: SearchResultItem.self) { item in
            ArchiveDetailView(archive: item, server: server)
        }
        .onChange(of: query) { _, newValue in
            hasSearched = false
            if isAddingTag { isAddingTag = false; return }
            if newValue.isEmpty { suggestions = [] }
            else { Task { await loadSuggestions() } }
        }
    }

    private var historyView: some View {
        let history = recentSearches
        return Group {
            if history.isEmpty {
                ContentUnavailableView("search_history_empty", systemImage: "clock.arrow.circlepath", description: Text("search_history_empty_desc"))
            } else {
                List {
                    Section(String(localized: "search_history")) {
                        ForEach(history, id: \.self) { entry in
                            Button {
                                query = entry.query
                                tags = entry.tags.map { (value: $0, label: $0, display: $0) }
                                DispatchQueue.main.async { performSearch() }
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath").foregroundColor(.secondary)
                                    Text(entry.query).foregroundColor(.primary)
                                    if !entry.tags.isEmpty {
                                        Spacer()
                                        Text("+\(entry.tags.count) \(String(localized: "search_tag_count"))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(String(localized: "delete"), role: .destructive) {
                                    var h = recentSearches
                                    h.removeAll { $0 == entry }
                                    recentSearches = h
                                }
                            }
                        }
                    }

                    Button(String(localized: "search_clear_history"), role: .destructive) {
                        showClearHistoryAlert = true
                    }
                    .alert(String(localized: "clear_history_confirm"), isPresented: $showClearHistoryAlert) {
                        Button(String(localized: "cancel"), role: .cancel) {}
                        Button(String(localized: "confirm"), role: .destructive) {
                            UserDefaults.standard.removeObject(forKey: historyKey)
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
                            tags.append((value: sug.value, label: sug.label, display: sug.display ?? sug.label))
                            suggestions.removeAll { $0.value == sug.value }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sug.label).foregroundColor(.primary)
                                if let display = sug.display, !display.isEmpty {
                                    Text(display).font(.caption).foregroundColor(.secondary)
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
                    VStack(spacing: 0) {
                        if let t = currentTags, !t.isEmpty {
                            HStack {
                                Spacer()
                                Text("(+\(t.components(separatedBy: ",").count) \(String(localized: "search_tag_count"))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                            }
                        }

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
    }

    private func onTagRemoved() {
        hasSearched = false
        let tagValues = Set(tags.map(\.value))
        suggestions = cachedSuggestions.filter { !tagValues.contains($0.value) }
    }

    private func performSearch() {
        guard !query.isEmpty || !tags.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        hasSearched = true
        suggestions = []
        results = []
        hasMore = true
        currentQuery = query
        currentTags = tags.isEmpty ? nil : tags.map(\.value).joined(separator: ",")
        nextStart = 0
        saveHistory(HistoryEntry(query: query, tags: tags.map(\.value)))
        Task { await doSearch() }
    }

    private func saveHistory(_ entry: HistoryEntry) {
        var history = recentSearches
        if !history.contains(entry) {
            history.insert(entry, at: 0)
            if history.count > 20 { history = Array(history.prefix(20)) }
            recentSearches = history
        }
    }

    private func doSearch() async {
        guard !isLoading else { return }
        isLoading = true
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        do {
            let result = try await server.apiClient.search(
                favoriteOnly: favoriteOnly, untaggedOnly: untaggedOnly, newonly: newOnly,
                groupbyTanks: true,
                filter: currentQuery.isEmpty ? nil : currentQuery,
                tags: currentTags,
                sortby: sortField, order: sortOrder,
                dateFrom: dateEnabled ? df.string(from: dateFrom) : nil,
                dateTo: dateEnabled ? df.string(from: dateTo) : nil,
                page: (nextStart / pageSize) + 1, pageSize: pageSize
            )
            let items = result.data ?? []
            nextStart = items.count
            results = items
            hasMore = items.count >= pageSize
            isLoading = false
        } catch {
            isLoading = false
        }
    }

    private func loadSuggestions() async {
        let lastWord: String
        if let lastSpace = query.lastIndex(of: " ") {
            lastWord = String(query[query.index(after: lastSpace)...])
        } else {
            lastWord = query
        }
        guard !lastWord.isEmpty else { suggestions = []; return }
        do { suggestions = try await server.apiClient.autocomplete(query: lastWord)
             cachedSuggestions = suggestions }
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
                favoriteOnly: favoriteOnly, untaggedOnly: untaggedOnly, newonly: newOnly,
                groupbyTanks: true,
                filter: currentQuery.isEmpty ? nil : currentQuery,
                tags: currentTags,
                sortby: sortField, order: sortOrder,
                dateFrom: dateEnabled ? df.string(from: dateFrom) : nil,
                dateTo: dateEnabled ? df.string(from: dateTo) : nil,
                page: (nextStart / pageSize) + 1, pageSize: pageSize
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
}

struct TagFlowView: View {
    @Binding var tags: [(value: String, label: String, display: String)]
    let onTagRemoved: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    tags.removeAll()
                    onTagRemoved()
                } label: {
                    Image(systemName: "xmark")
                        // .font(.title3)
                }
                .buttonStyle(.glass)

                ForEach(tags.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Button {
                            tags.remove(at: i)
                            DispatchQueue.main.async { onTagRemoved() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .buttonStyle(.plain)

                        Text(tags[i].display)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .clipShape(Capsule())
                    .fixedSize()
                }
                .glassEffect(.regular)
            }
        }
        .frame(height: 28)
    }
}
