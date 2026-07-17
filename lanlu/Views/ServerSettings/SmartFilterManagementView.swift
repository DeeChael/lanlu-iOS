import SwiftUI

struct SmartFilterManagementView: View {
    private enum EditorRoute: Identifiable {
        case create
        case edit(APIClient.SmartFilterItem)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let filter): "edit-\(filter.id)"
            }
        }
    }

    let server: Server

    @State private var filters: [APIClient.SmartFilterItem] = []
    @State private var enabledStates: [Int: Bool] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var editorRoute: EditorRoute?
    @State private var filterPendingDeletion: APIClient.SmartFilterItem?
    @State private var togglingFilterIds: Set<Int> = []
    @State private var lastSubmittedOrder: [Int] = []
    @State private var isEditingOrder = false

    var body: some View {
        List {
            Section {
                Toggle(
                    String(localized: "smart_filter_edit_order"),
                    isOn: $isEditingOrder
                )
            }

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
                    enabled: enabledBinding(for: filter),
                    isToggling: togglingFilterIds.contains(filter.id)
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        filterPendingDeletion = filter
                    } label: {
                        Image(
                            systemName: "trash"
                        )
                    }

                    Button {
                        editorRoute = .edit(filter)
                    } label: {
                        Image(
                            systemName: "pencil"
                        )
                    }
                    .tint(.accentColor)
                }
            }
            .onMove { source, destination in
                filters.move(fromOffsets: source, toOffset: destination)
            }

            if let errorMessage, filters.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .environment(
            \.editMode,
            .constant(isEditingOrder ? .active : .inactive)
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editorRoute = .create
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            SmartFilterEditorView(
                server: server,
                filter: {
                    if case .edit(let filter) = route { return filter }
                    return nil
                }(),
                onSaved: {
                    Task { await loadFilters() }
                }
            )
                .presentationDetents([.large])
        }
        .alert(
            String(localized: "smart_filter_delete_title"),
            isPresented: deleteAlertPresented,
            presenting: filterPendingDeletion
        ) { filter in
            Button(String(localized: "delete"), role: .destructive) {
                deleteFilter(filter)
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: { filter in
            Text(
                String(
                    format: String(localized: "smart_filter_delete_confirm"),
                    filter.name
                )
            )
        }
        .alert(
            String(localized: "error_title"),
            isPresented: errorAlertPresented
        ) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadFilters()
        }
        .onChange(of: isEditingOrder) { wasEditing, isEditing in
            if wasEditing && !isEditing {
                submitCurrentOrderIfNeeded()
            }
        }
        .onDisappear {
            submitCurrentOrderIfNeeded()
        }
    }

    private func enabledBinding(for filter: APIClient.SmartFilterItem) -> Binding<Bool> {
        Binding(
            get: { enabledStates[filter.id] ?? filter.enabled ?? false },
            set: { toggleFilter(filter, targetValue: $0) }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { filterPendingDeletion != nil },
            set: { if !$0 { filterPendingDeletion = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func toggleFilter(
        _ filter: APIClient.SmartFilterItem,
        targetValue: Bool
    ) {
        guard !togglingFilterIds.contains(filter.id) else { return }
        let previousValue = enabledStates[filter.id] ?? filter.enabled ?? false
        enabledStates[filter.id] = targetValue
        togglingFilterIds.insert(filter.id)

        Task {
            do {
                try await server.apiClient.toggleAdminSmartFilter(id: filter.id)
                LogManager.shared.log("[SmartFilters] Toggle completed id=\(filter.id)")
            } catch {
                enabledStates[filter.id] = previousValue
                errorMessage = error.localizedDescription
                LogManager.shared.log("[SmartFilters] Toggle failed: \(error.localizedDescription)")
            }
            togglingFilterIds.remove(filter.id)
        }
    }

    private func deleteFilter(_ filter: APIClient.SmartFilterItem) {
        Task {
            do {
                try await server.apiClient.deleteAdminSmartFilter(id: filter.id)
                filters.removeAll { $0.id == filter.id }
                enabledStates.removeValue(forKey: filter.id)
                lastSubmittedOrder = filters.map(\.id)
                LogManager.shared.log("[SmartFilters] Delete completed id=\(filter.id)")
            } catch {
                errorMessage = error.localizedDescription
                LogManager.shared.log("[SmartFilters] Delete failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadFilters() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await server.apiClient.fetchAdminSmartFilters()
                .sorted {
                    ($0.sortOrderNumber ?? Int.max) < ($1.sortOrderNumber ?? Int.max)
                }
            filters = loaded
            lastSubmittedOrder = loaded.map(\.id)
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

    private func submitCurrentOrderIfNeeded() {
        let currentOrder = filters.map(\.id)
        guard !currentOrder.isEmpty,
              currentOrder != lastSubmittedOrder else { return }

        let previousSubmittedOrder = lastSubmittedOrder
        lastSubmittedOrder = currentOrder
        let payload = currentOrder.enumerated().map { index, id in
            APIClient.SmartFilterOrderItem(id: id, sortOrderNumber: index)
        }
        Task {
            do {
                try await server.apiClient.reorderAdminSmartFilters(payload)
                LogManager.shared.log("[SmartFilters] Reorder completed")
            } catch {
                if lastSubmittedOrder == currentOrder {
                    lastSubmittedOrder = previousSubmittedOrder
                }
                LogManager.shared.log("[SmartFilters] Reorder failed: \(error.localizedDescription)")
            }
        }
    }
}

private struct SmartFilterRow: View {
    let filter: APIClient.SmartFilterItem
    @Binding var enabled: Bool
    let isToggling: Bool

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
                .disabled(isToggling)
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

private struct SmartFilterEditorView: View {
    private static let iconOptions: [(value: String, systemImage: String, title: String)] = [
        ("BookOpen", "book", "BookOpen"),
        ("Tag", "tag", "Tag"),
        ("Calendar", "calendar", "Calendar"),
        ("Search", "magnifyingglass", "Search"),
        ("Clock", "clock", "Clock"),
        ("Star", "star", "Star"),
        ("Filter", "line.3.horizontal.decrease", "Filter")
    ]

    private static let sortOptions: [(value: String, localizationKey: String)] = [
        ("", "smart_filter_sort_default"),
        ("created_at", "smart_filter_sort_created"),
        ("release_at", "smart_filter_sort_release"),
        ("updated_at", "smart_filter_sort_updated"),
        ("lastread", "smart_filter_sort_last_read"),
        ("pagecount", "smart_filter_sort_pages")
    ]

    let server: Server
    let filter: APIClient.SmartFilterItem?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var query: String
    @State private var sortBy: String
    @State private var sortOrder: String
    @State private var dateFrom: Int
    @State private var dateTo: Int
    @State private var newOnly: Bool
    @State private var untaggedOnly: Bool
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        server: Server,
        filter: APIClient.SmartFilterItem?,
        onSaved: @escaping () -> Void
    ) {
        self.server = server
        self.filter = filter
        self.onSaved = onSaved
        _name = State(initialValue: filter?.name ?? "")
        _icon = State(initialValue: filter?.icon ?? "Filter")
        _query = State(initialValue: filter?.query ?? "")
        _sortBy = State(initialValue: filter?.sortBy ?? "")
        _sortOrder = State(initialValue: filter?.sortOrder ?? "desc")
        _dateFrom = State(initialValue: min(filter?.dateFrom ?? -7, 0))
        _dateTo = State(initialValue: min(filter?.dateTo ?? 0, 0))
        _newOnly = State(initialValue: filter?.newOnly ?? false)
        _untaggedOnly = State(initialValue: filter?.untaggedOnly ?? false)
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(String(localized: "smart_filter_name"), text: $name)

                    Picker(String(localized: "smart_filter_icon"), selection: $icon) {
                        ForEach(Self.iconOptions, id: \.value) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option.value)
                        }
                    }

                    TextField(String(localized: "smart_filter_query"), text: $query)

                    Picker(String(localized: "smart_filter_sort_by"), selection: $sortBy) {
                        ForEach(Self.sortOptions, id: \.value) { option in
                            Text(String(localized: String.LocalizationValue(option.localizationKey)))
                                .tag(option.value)
                        }
                    }

                    Picker(String(localized: "smart_filter_sort_order"), selection: $sortOrder) {
                        Text(String(localized: "sort_asc")).tag("asc")
                        Text(String(localized: "sort_desc")).tag("desc")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    relativeDayStepper(
                        String(localized: "smart_filter_date_from"),
                        value: $dateFrom
                    )
                    relativeDayStepper(
                        String(localized: "smart_filter_date_to"),
                        value: $dateTo
                    )
                } footer: {
                    Text(String(localized: "smart_filter_relative_day_help"))
                }

                Section {
                    Toggle(String(localized: "smart_filter_new_only_full"), isOn: $newOnly)
                    Toggle(String(localized: "smart_filter_untagged_only_full"), isOn: $untaggedOnly)
                }
            }
                .navigationTitle(
                    String(localized: filter == nil ? "smart_filter_add" : "smart_filter_edit")
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .confirm) {
                            submit()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(!canSubmit)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .alert(
                    String(localized: "error_title"),
                    isPresented: errorAlertPresented
                ) {
                    Button(String(localized: "ok")) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func relativeDayStepper(
        _ title: String,
        value: Binding<Int>
    ) -> some View {
        Stepper {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } onIncrement: {
            value.wrappedValue = min(0, value.wrappedValue + 1)
        } onDecrement: {
            if value.wrappedValue > Int.min {
                value.wrappedValue -= 1
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = APIClient.SmartFilterPayload(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon,
            query: trimmedQuery.isEmpty ? nil : trimmedQuery,
            sortBy: sortBy,
            sortOrder: sortOrder,
            dateFrom: dateFrom,
            dateTo: dateTo,
            newOnly: newOnly,
            untaggedOnly: untaggedOnly
        )

        Task {
            do {
                if let filter {
                    try await server.apiClient.updateAdminSmartFilter(
                        id: filter.id,
                        payload: payload
                    )
                } else {
                    try await server.apiClient.createAdminSmartFilter(payload)
                }
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
                LogManager.shared.log("[SmartFilters] Save failed: \(error.localizedDescription)")
            }
        }
    }
}
