import SwiftUI
import UniformTypeIdentifiers

struct SmartFilterManagementView: View {
    let server: Server

    @State private var filters: [APIClient.SmartFilterItem] = []
    @State private var enabledStates: [Int: Bool] = [:]
    @State private var originalOrder: [Int] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddFilter = false
    @State private var didSubmitOrder = false
    @State private var draggedFilterID: Int?

    var body: some View {
        List {
            if isLoading && filters.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            ForEach(filters) { filter in
                SmartFilterRow(
                    filter: filter,
                    enabled: enabledBinding(for: filter)
                )
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
                .onDrag {
                    draggedFilterID = filter.id
                    return NSItemProvider(object: String(filter.id) as NSString)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: SmartFilterDropDelegate(
                        destinationID: filter.id,
                        filters: $filters,
                        draggedFilterID: $draggedFilterID
                    )
                )
            }

            if let errorMessage, filters.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddFilter = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showAddFilter) {
            AddSmartFilterView()
                .presentationDetents([.large])
        }
        .task {
            await loadFilters()
        }
        .onDisappear {
            submitOrderIfNeeded()
        }
    }

    private func enabledBinding(for filter: APIClient.SmartFilterItem) -> Binding<Bool> {
        Binding(
            get: { enabledStates[filter.id] ?? filter.enabled ?? false },
            set: { enabledStates[filter.id] = $0 }
        )
    }

    private func loadFilters() async {
        isLoading = true
        errorMessage = nil
        didSubmitOrder = false
        do {
            let loaded = try await server.apiClient.fetchAdminSmartFilters()
                .sorted {
                    ($0.sortOrderNumber ?? Int.max) < ($1.sortOrderNumber ?? Int.max)
                }
            filters = loaded
            originalOrder = loaded.map(\.id)
            enabledStates = Dictionary(
                uniqueKeysWithValues: loaded.map { ($0.id, $0.enabled ?? false) }
            )
            LogManager.shared.log("[SmartFilters] Load completed count=\(loaded.count)")
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[SmartFilters] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func submitOrderIfNeeded() {
        let currentOrder = filters.map(\.id)
        guard !didSubmitOrder,
              !originalOrder.isEmpty,
              currentOrder != originalOrder else { return }

        didSubmitOrder = true
        let payload = currentOrder.enumerated().map { index, id in
            APIClient.SmartFilterOrderItem(id: id, sortOrderNumber: index)
        }
        Task {
            do {
                try await server.apiClient.reorderAdminSmartFilters(payload)
                LogManager.shared.log("[SmartFilters] Reorder completed")
            } catch {
                LogManager.shared.log("[SmartFilters] Reorder failed: \(error.localizedDescription)")
            }
        }
    }
}

private struct SmartFilterDropDelegate: DropDelegate {
    let destinationID: Int
    @Binding var filters: [APIClient.SmartFilterItem]
    @Binding var draggedFilterID: Int?

    func dropEntered(info: DropInfo) {
        guard let draggedFilterID,
              draggedFilterID != destinationID,
              let sourceIndex = filters.firstIndex(where: { $0.id == draggedFilterID }),
              let destinationIndex = filters.firstIndex(where: { $0.id == destinationID }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            filters.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: destinationIndex > sourceIndex
                    ? destinationIndex + 1
                    : destinationIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedFilterID = nil
        return true
    }
}

private struct SmartFilterRow: View {
    let filter: APIClient.SmartFilterItem
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(filter.name)
                        .fontWeight(.medium)

                    if filter.newOnly == true {
                        statusBadge(
                            String(localized: "smart_filter_new_only"),
                            color: .blue
                        )
                    }
                    if filter.untaggedOnly == true {
                        statusBadge(
                            String(localized: "smart_filter_untagged_only"),
                            color: .orange
                        )
                    }
                }

                Text(
                    String(
                        format: String(localized: "smart_filter_sort_method"),
                        sortTitle
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(filter.sortOrder == "asc"
                     ? String(localized: "sort_asc")
                     : String(localized: "sort_desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $enabled)
                .labelsHidden()
        }
        .padding(.vertical, 3)
    }

    private var systemImage: String {
        switch filter.icon {
        case "BookOpen": "book"
        case "Tag": "tag"
        case "Calendar": "calendar"
        case "Search": "magnifyingglass"
        case "Clock": "clock"
        case "Star": "star"
        case "Filter": "line.3.horizontal.decrease"
        default: "line.3.horizontal.decrease"
        }
    }

    private var sortTitle: String {
        switch filter.sortBy ?? "" {
        case "": String(localized: "smart_filter_sort_default")
        case "date_added", "created_at": String(localized: "smart_filter_sort_created")
        case "lastread", "lastreadtime": String(localized: "smart_filter_sort_last_read")
        case "title": String(localized: "smart_filter_sort_title")
        case "release_at": String(localized: "smart_filter_sort_release")
        case "updated_at": String(localized: "smart_filter_sort_updated")
        case "pagecount": String(localized: "smart_filter_sort_pages")
        default: String(localized: "smart_filter_sort_unknown")
        }
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(color.opacity(0.22)), in: Capsule())
    }
}

private struct AddSmartFilterView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle(String(localized: "smart_filter_add"))
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
