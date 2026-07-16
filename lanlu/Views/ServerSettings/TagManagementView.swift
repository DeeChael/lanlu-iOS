import SwiftUI

struct TagManagementView: View {
    let server: Server

    @AppStorage("language") private var language = "system"

    @State private var tags: [APIClient.TagItem] = []
    @State private var namespaces: [String] = []
    @State private var searchText = ""
    @State private var selectedNamespace: String?
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var nextOffset = 0
    @State private var errorMessage: String?
    @State private var showFilter = false
    @State private var loadTask: Task<Void, Never>?
    @State private var requestID = UUID()

    private let batchLimit = 100

    var body: some View {
        List {
            Section {
                ForEach(tags) { tag in
                    TagManagementRow(tag: tag, translationLanguage: translationLanguage)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {} label: {
                                Image(
                                    systemName: "trash"
                                )
                            }

                            Button {} label: {
                                Image(
                                    systemName: "pencil"
                                )
                            }
                            .tint(.accentColor)
                        }
                        .onAppear {
                            loadMoreIfNeeded(tag)
                        }
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                if let errorMessage, tags.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "search_prompt"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            TagFilterView(
                namespaces: namespaces,
                selectedNamespace: $selectedNamespace
            )
            .presentationDetents([.medium])
        }
        .task {
            reloadTags()
            await loadNamespaces()
        }
        .onChange(of: searchText) { _, _ in
            reloadTags()
        }
        .onChange(of: selectedNamespace) { _, _ in
            reloadTags()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private var translationLanguage: String {
        if language.hasPrefix("zh") { return "zh" }
        if language == "en" { return "en" }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
    }

    private func loadNamespaces() async {
        do {
            namespaces = try await server.apiClient.fetchTagNamespaces()
            LogManager.shared.log("[Tags] Namespaces loaded count=\(namespaces.count)")
        } catch {
            LogManager.shared.log("[Tags] Namespaces load failed: \(error.localizedDescription)")
        }
    }

    private func reloadTags() {
        loadTask?.cancel()
        let newRequestID = UUID()
        requestID = newRequestID
        tags = []
        nextOffset = 0
        hasMore = true
        errorMessage = nil
        isLoading = false

        loadTask = Task {
            await loadNextPage(requestID: newRequestID)
        }
    }

    private func loadMoreIfNeeded(_ tag: APIClient.TagItem) {
        guard hasMore, !isLoading,
              let index = tags.firstIndex(where: { $0.id == tag.id }),
              index >= tags.count - 10 else { return }

        let currentRequestID = requestID
        loadTask = Task {
            await loadNextPage(requestID: currentRequestID)
        }
    }

    @MainActor
    private func loadNextPage(requestID expectedRequestID: UUID) async {
        guard expectedRequestID == requestID, hasMore, !isLoading else { return }
        isLoading = true
        let offset = nextOffset

        do {
            let result = try await server.apiClient.fetchTags(
                limit: batchLimit,
                offset: offset,
                search: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                namespace: selectedNamespace
            )
            guard !Task.isCancelled, expectedRequestID == requestID else { return }

            let existingIDs = Set(tags.map(\.id))
            tags.append(contentsOf: result.items.filter { !existingIDs.contains($0.id) })
            nextOffset = result.offset + result.limit
            hasMore = !result.items.isEmpty && nextOffset < result.total
            LogManager.shared.log("[Tags] Batch loaded offset=\(offset) received=\(result.items.count) nextOffset=\(nextOffset) total=\(result.total)")
        } catch {
            guard !Task.isCancelled, expectedRequestID == requestID else { return }
            errorMessage = error.localizedDescription
            hasMore = false
            LogManager.shared.log("[Tags] Batch load failed offset=\(offset): \(error.localizedDescription)")
        }

        if expectedRequestID == requestID {
            isLoading = false
        }
    }
}

private struct TagManagementRow: View {
    let tag: APIClient.TagItem
    let translationLanguage: String

    private var translatedTitle: String? {
        guard let text = tag.translations?[translationLanguage]?.text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                if let namespace = tag.namespace, !namespace.isEmpty {
                    Text(namespace)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: Capsule())
                }

                Text(translatedTitle ?? tag.name)
            }

            if translatedTitle != nil {
                Text(tag.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TagFilterView: View {
    let namespaces: [String]
    @Binding var selectedNamespace: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker(String(localized: "tag_namespace"), selection: $selectedNamespace) {
                    Text(String(localized: "tag_all_namespaces"))
                        .tag(String?.none)
                    ForEach(namespaces, id: \.self) { namespace in
                        Text(namespace)
                            .tag(Optional(namespace))
                    }
                }
            }
            .navigationTitle(String(localized: "filter_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}
