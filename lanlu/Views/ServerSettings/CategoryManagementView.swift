import SwiftUI

private func normalizedPluginNamespace(_ namespace: String) -> String {
    namespace.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

struct CategoryManagementView: View {
    private enum EditorRoute: Identifiable {
        case create
        case edit(APIClient.CategoryItem)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let category): "edit-\(category.id)"
            }
        }
    }

    private enum PendingAction: Identifiable {
        case delete(APIClient.CategoryItem)
        case scan(APIClient.CategoryItem)
        case scanAll

        var id: String {
            switch self {
            case .delete(let category): "delete-\(category.id)"
            case .scan(let category): "scan-\(category.id)"
            case .scanAll: "scan-all"
            }
        }
    }

    let server: Server

    @State private var categories: [APIClient.CategoryItem] = []
    @State private var enabledStates: [Int: Bool] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var plugins: [APIClient.AdminPlugin] = []
    @State private var editorRoute: EditorRoute?
    @State private var pendingAction: PendingAction?
    @State private var isPerformingAction = false
    @State private var updatingEnabledCategoryIds: Set<Int> = []

    var body: some View {
        List {
            if isLoading && categories.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            ForEach(categories, id: \.id) { category in
                CategoryManagementRow(
                    server: server,
                    category: category,
                    enabled: enabledBinding(for: category),
                    isUpdatingEnabled: updatingEnabledCategoryIds.contains(category.id)
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingAction = .delete(category)
                    } label: {
                        Image(
                            systemName: "trash"
                        )
                    }

                    Button {
                        editorRoute = .edit(category)
                    } label: {
                        Image(
                            systemName: "pencil"
                        )
                    }
                    .tint(.accentColor)

                    Button {
                        pendingAction = .scan(category)
                    } label: {
                        Image(
                            systemName: "play"
                        )
                    }
                    .tint(.green)
                }
            }

        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    pendingAction = .scanAll
                } label: {
                    if isPerformingAction {
                        ProgressView()
                    } else {
                        Image(systemName: "play")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isPerformingAction)
            }
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
            CategoryEditorView(
                server: server,
                category: {
                    if case .edit(let category) = route { return category }
                    return nil
                }(),
                plugins: plugins,
                onSaved: {
                    Task { await loadCategories() }
                }
            )
                .presentationDetents([.large])
        }
        .alert(item: $pendingAction) { action in
            switch action {
            case .delete(let category):
                Alert(
                    title: Text(String(localized: "category_delete_title")),
                    message: Text(
                        String(
                            format: String(localized: "category_delete_confirm"),
                            category.name
                        )
                    ),
                    primaryButton: .destructive(Text(String(localized: "delete"))) {
                        perform(action)
                    },
                    secondaryButton: .cancel()
                )
            case .scan(let category):
                Alert(
                    title: Text(String(localized: "category_scan_title")),
                    message: Text(
                        String(
                            format: String(localized: "category_scan_confirm"),
                            category.name
                        )
                    ),
                    primaryButton: .default(Text(String(localized: "confirm_action"))) {
                        perform(action)
                    },
                    secondaryButton: .cancel()
                )
            case .scanAll:
                Alert(
                    title: Text(String(localized: "category_scan_all_title")),
                    message: Text(String(localized: "category_scan_all_confirm")),
                    primaryButton: .default(Text(String(localized: "confirm_action"))) {
                        perform(action)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .alert(
            String(localized: "error_title"),
            isPresented: errorAlertPresented
        ) {
            Button(String(localized: "ok")) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadInitialData()
        }
    }

    private func enabledBinding(for category: APIClient.CategoryItem) -> Binding<Bool> {
        Binding(
            get: { enabledStates[category.id] ?? category.enabled ?? false },
            set: { updateEnabled($0, for: category) }
        )
    }

    private func updateEnabled(_ enabled: Bool, for category: APIClient.CategoryItem) {
        guard !updatingEnabledCategoryIds.contains(category.id) else { return }
        let previousValue = enabledStates[category.id] ?? category.enabled ?? false
        enabledStates[category.id] = enabled
        updatingEnabledCategoryIds.insert(category.id)

        Task {
            do {
                try await server.apiClient.updateCategory(
                    catid: category.catid,
                    payload: APIClient.UpdateCategoryPayload(
                        name: nil,
                        scanPath: nil,
                        description: nil,
                        icon: nil,
                        sortOrder: nil,
                        plugins: nil,
                        enabled: enabled
                    )
                )
                LogManager.shared.log(
                    "[Categories] Enabled updated id=\(category.id) enabled=\(enabled)"
                )
            } catch {
                enabledStates[category.id] = previousValue
                errorMessage = error.localizedDescription
                LogManager.shared.log(
                    "[Categories] Enabled update failed id=\(category.id): \(error.localizedDescription)"
                )
            }
            updatingEnabledCategoryIds.remove(category.id)
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadCategories() async {
        isLoading = true
        errorMessage = nil
        LogManager.shared.log("[Categories] Load started")
        do {
            let loadedCategories = try await server.apiClient.fetchCategories()
            categories = loadedCategories
            enabledStates = Dictionary(
                uniqueKeysWithValues: loadedCategories.map { ($0.id, $0.enabled ?? false) }
            )
            for category in loadedCategories {
                LogManager.shared.log(
                    "[Categories] Decoded category id=\(category.id) catid=\(category.catid) name=\(category.name) plugins=\(category.plugins ?? [])"
                )
            }
            LogManager.shared.log("[Categories] Load completed count=\(loadedCategories.count)")
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[Categories] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func loadInitialData() async {
        if let cached = CacheManager.shared.getAdminPlugins(serverId: server.baseURL),
           let cachedPlugins = try? JSONDecoder().decode([APIClient.AdminPlugin].self, from: cached) {
            plugins = metadataPlugins(from: cachedPlugins)
        }

        async let categoryLoad: Void = loadCategories()
        async let pluginLoad: Void = loadPlugins()
        _ = await (categoryLoad, pluginLoad)
    }

    private func loadPlugins() async {
        do {
            let loadedPlugins = try await server.apiClient.fetchAdminPlugins()
            let filteredPlugins = metadataPlugins(from: loadedPlugins)
            plugins = filteredPlugins
            if let data = try? JSONEncoder().encode(filteredPlugins) {
                CacheManager.shared.cacheAdminPlugins(serverId: server.baseURL, data: data)
            }
            LogManager.shared.log("[Categories] Metadata plugins loaded count=\(filteredPlugins.count)")
            LogManager.shared.log(
                "[Categories] Metadata plugin namespaces=\(filteredPlugins.map(\.namespace))"
            )
        } catch {
            LogManager.shared.log("[Categories] Plugins load failed: \(error.localizedDescription)")
            if plugins.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func metadataPlugins(
        from plugins: [APIClient.AdminPlugin]
    ) -> [APIClient.AdminPlugin] {
        plugins.filter {
            $0.pluginType?.caseInsensitiveCompare("Metadata") == .orderedSame
        }
    }

    private func perform(_ action: PendingAction) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        errorMessage = nil

        Task {
            do {
                switch action {
                case .delete(let category):
                    LogManager.shared.log("[Categories] Delete started id=\(category.id)")
                    try await server.apiClient.deleteCategory(id: category.id)
                    categories.removeAll { $0.id == category.id }
                    enabledStates.removeValue(forKey: category.id)
                    LogManager.shared.log("[Categories] Delete completed id=\(category.id)")
                case .scan(let category):
                    LogManager.shared.log("[Categories] Scan started id=\(category.id)")
                    try await server.apiClient.scanCategory(id: category.id)
                    LogManager.shared.log("[Categories] Scan requested id=\(category.id)")
                case .scanAll:
                    LogManager.shared.log("[Categories] Full scan started")
                    try await server.apiClient.scanCategories()
                    LogManager.shared.log("[Categories] Full scan requested")
                }
            } catch {
                errorMessage = error.localizedDescription
                LogManager.shared.log("[Categories] Action failed: \(error.localizedDescription)")
            }
            isPerformingAction = false
        }
    }
}

private struct CategoryManagementRow: View {
    let server: Server
    let category: APIClient.CategoryItem
    @Binding var enabled: Bool
    let isUpdatingEnabled: Bool

    @State private var coverImage: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if coverImage == nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(category.name)
                            .fontWeight(.medium)
                        archiveCountBadge
                    }

                    if let description = category.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }

            Spacer(minLength: 8)

            if coverImage != nil {
                archiveCountBadge
            }

            Toggle("", isOn: $enabled)
                .labelsHidden()
                .disabled(isUpdatingEnabled)
        }
        .frame(minHeight: 72)
        .background(alignment: .leading) {
            if let coverImage {
                GeometryReader { proxy in
                    Image(uiImage: coverImage)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width * 2 / 3,
                            height: proxy.size.height,
                            alignment: .leading
                        )
                        .clipped()
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.5),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        }
                }
            }
        }
        .task(id: category.coverAssetId) {
            await loadCover()
        }
    }

    private var archiveCountBadge: some View {
        Text(String(format: String(localized: "category_archive_count"), category.archiveCount ?? 0))
            .font(.caption2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassEffect(.regular, in: Capsule())
    }

    private func loadCover() async {
        guard let assetId = category.coverAssetId else {
            coverImage = nil
            return
        }
        guard let data = try? await server.apiClient.fetchAsset(assetId: assetId),
              let image = UIImage(data: data) else {
            coverImage = nil
            LogManager.shared.log("[Categories] Cover unavailable assetId=\(assetId)")
            return
        }
        coverImage = image
    }
}

private struct CategoryEditorView: View {
    let server: Server
    let category: APIClient.CategoryItem?
    let plugins: [APIClient.AdminPlugin]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var scanPath: String
    @State private var categoryDescription: String
    @State private var sortOrder: Int
    @State private var enabledPluginNamespaces: [String]
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var editMode: EditMode = .active

    init(
        server: Server,
        category: APIClient.CategoryItem?,
        plugins: [APIClient.AdminPlugin],
        onSaved: @escaping () -> Void
    ) {
        self.server = server
        self.category = category
        self.plugins = plugins
        self.onSaved = onSaved
        _name = State(initialValue: category?.name ?? "")
        _scanPath = State(initialValue: category?.scanPath ?? "")
        _categoryDescription = State(initialValue: category?.description ?? "")
        _sortOrder = State(initialValue: category?.sortOrder ?? 0)

        let canonicalNamespaces = Dictionary(
            uniqueKeysWithValues: plugins.map {
                (normalizedPluginNamespace($0.namespace), $0.namespace)
            }
        )
        var seenNamespaces = Set<String>()
        let enabledNamespaces = (category?.plugins ?? []).compactMap { namespace -> String? in
            let normalized = normalizedPluginNamespace(namespace)
            guard !normalized.isEmpty, seenNamespaces.insert(normalized).inserted else {
                return nil
            }
            return canonicalNamespaces[normalized]
                ?? namespace.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _enabledPluginNamespaces = State(initialValue: enabledNamespaces)

        let categoryNamespaces = category?.plugins ?? []
        let availableNamespaces = plugins.map(\.namespace).filter { namespace in
            !enabledNamespaces.contains {
                normalizedPluginNamespace($0) == normalizedPluginNamespace(namespace)
            }
        }
        LogManager.shared.log(
            "[Categories] Editor opened catid=\(category?.catid ?? "new") categoryPlugins=\(categoryNamespaces) metadataPlugins=\(plugins.map(\.namespace)) enabled=\(enabledNamespaces) available=\(availableNamespaces)"
        )
    }

    private var availablePlugins: [APIClient.AdminPlugin] {
        let enabledNamespaces = Set(
            enabledPluginNamespaces.map(normalizedPluginNamespace)
        )
        return plugins.filter {
            !enabledNamespaces.contains(normalizedPluginNamespace($0.namespace))
        }
    }

    private var pluginsByNamespace: [String: APIClient.AdminPlugin] {
        Dictionary(
            uniqueKeysWithValues: plugins.map {
                (normalizedPluginNamespace($0.namespace), $0)
            }
        )
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !scanPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(String(localized: "category_name"), text: $name)
                        .submitLabel(.done)
                        .scrollDismissesKeyboard(.immediately)
                }
                Section {
                    TextField(String(localized: "category_scan_path"), text: $scanPath)
                        .submitLabel(.done)
                        .scrollDismissesKeyboard(.immediately)
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "category_description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $categoryDescription)
                            .frame(minHeight: 96)
                            .scrollDismissesKeyboard(.immediately)
                    }
                }
                Section {
                    Stepper(value: $sortOrder) {
                        HStack {
                            Text(String(localized: "category_sort_order"))
                            Spacer()
                            Text("\(sortOrder)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                if !enabledPluginNamespaces.isEmpty {
                    Section(String(localized: "category_metadata_plugins")) {
                        ForEach(enabledPluginNamespaces, id: \.self) { namespace in
                            enabledPluginRow(namespace: namespace)
                                .id("enabled-\(namespace)")
                        }
                        .onMove { source, destination in
                            enabledPluginNamespaces.move(
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                    }
                    .id(enabledPluginListIdentity)
                }

                if enabledPluginNamespaces.isEmpty {
                    Section(String(localized: "category_metadata_plugins")) {
                        availablePluginRows
                    }
                } else {
                    Section {
                        availablePluginRows
                    }
                }

            }
                .environment(\.editMode, $editMode)
                .navigationTitle(
                    String(localized: category == nil ? "create_category" : "edit_category")
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
                    Button(String(localized: "ok")) {
                        errorMessage = nil
                    }
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    private var enabledPluginListIdentity: String {
        enabledPluginNamespaces.sorted().joined(separator: "|")
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func enabledPluginRow(namespace: String) -> some View {
        let normalizedNamespace = normalizedPluginNamespace(namespace)
        return HStack {
            Text(pluginsByNamespace[normalizedNamespace]?.name ?? namespace)
            Spacer()
            Button {
                enabledPluginNamespaces.removeAll {
                    normalizedPluginNamespace($0) == normalizedNamespace
                }
                refreshPluginEditMode()
            } label: {
                Image(systemName: "minus")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func availablePluginRow(_ plugin: APIClient.AdminPlugin) -> some View {
        HStack {
            Text(plugin.name)
            Spacer()
            Button {
                let normalizedNamespace = normalizedPluginNamespace(plugin.namespace)
                guard !enabledPluginNamespaces.contains(where: {
                    normalizedPluginNamespace($0) == normalizedNamespace
                }) else { return }
                enabledPluginNamespaces.append(plugin.namespace)
                refreshPluginEditMode()
            } label: {
                Image(systemName: "plus")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.green)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var availablePluginRows: some View {
        ForEach(availablePlugins, id: \.namespace) { plugin in
            availablePluginRow(plugin)
                .id("available-\(plugin.namespace)")
        }
    }

    private func refreshPluginEditMode() {
        editMode = .inactive
        DispatchQueue.main.async {
            editMode = .active
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil

        let submittedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedScanPath = scanPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedPlugins = enabledPluginNamespaces

        Task {
            do {
                if let category {
                    let payload = APIClient.UpdateCategoryPayload(
                        name: submittedName,
                        scanPath: submittedScanPath,
                        description: categoryDescription,
                        icon: category.icon ?? "",
                        sortOrder: sortOrder,
                        plugins: submittedPlugins,
                        enabled: category.enabled ?? false
                    )
                    try await server.apiClient.updateCategory(
                        catid: category.catid,
                        payload: payload
                    )
                    LogManager.shared.log(
                        "[Categories] Update completed catid=\(category.catid)"
                    )
                } else {
                    let payload = APIClient.CreateCategoryPayload(
                        name: submittedName,
                        scanPath: submittedScanPath,
                        description: categoryDescription,
                        icon: "",
                        sortOrder: sortOrder,
                        plugins: submittedPlugins
                    )
                    try await server.apiClient.createCategory(payload)
                    LogManager.shared.log("[Categories] Create completed")
                }
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                LogManager.shared.log("[Categories] Save failed: \(error.localizedDescription)")
                isSubmitting = false
            }
        }
    }
}
