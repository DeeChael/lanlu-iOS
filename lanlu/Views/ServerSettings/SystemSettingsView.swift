import SwiftUI

private enum SystemSettingCategory: String, CaseIterable, Identifiable {
    case cron
    case storage
    case performance
    case server
    case ssl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cron: String(localized: "system_settings_cron")
        case .storage: String(localized: "system_settings_storage")
        case .performance: String(localized: "system_settings_performance")
        case .server: String(localized: "system_settings_server")
        case .ssl: String(localized: "system_settings_ssl")
        }
    }

    var systemImage: String {
        switch self {
        case .cron: "timer"
        case .storage: "folder"
        case .performance: "bolt"
        case .server: "server.rack"
        case .ssl: "lock"
        }
    }
}

struct SystemSettingsView: View {
    let server: Server

    @State private var settings: [APIClient.SystemSettingItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if isLoading && settings.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(SystemSettingCategory.allCases) { category in
                        NavigationLink {
                            SystemSettingCategoryView(
                                server: server,
                                category: category,
                                settings: settings.filter { $0.category == category.rawValue }
                            )
                        } label: {
                            Label(category.title, systemImage: category.systemImage)
                        }
                    }
                }
            }
        }
        .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadSettings()
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadSettings() async {
        isLoading = true
        errorMessage = nil
        do {
            settings = try await server.apiClient.fetchAdminSystemSettings()
            LogManager.shared.log("[SystemSettings] Load completed count=\(settings.count)")
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[SystemSettings] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }
}

private struct SystemSettingCategoryView: View {
    let server: Server
    let category: SystemSettingCategory
    let settings: [APIClient.SystemSettingItem]

    @State private var values: [String: String]
    @State private var savedValues: [String: String]
    @State private var integerSetting: APIClient.SystemSettingItem?
    @State private var integerInput = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        server: Server,
        category: SystemSettingCategory,
        settings: [APIClient.SystemSettingItem]
    ) {
        self.server = server
        self.category = category
        self.settings = settings.sorted { $0.id < $1.id }
        let initialValues = Dictionary(
            uniqueKeysWithValues: settings.map { ($0.key, $0.value) }
        )
        _values = State(initialValue: initialValues)
        _savedValues = State(initialValue: initialValues)
    }

    private var changedValues: [String: String] {
        values.filter { savedValues[$0.key] != $0.value }
    }

    var body: some View {
        List {
            ForEach(settings) { setting in
                settingSection(setting)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .confirm) {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(changedValues.isEmpty || isSaving)
            }
        }
        .alert(
            localizedDescription(for: integerSetting),
            isPresented: integerInputAlertPresented
        ) {
            TextField(String(localized: "system_settings_integer_value"), text: $integerInput)
                .keyboardType(.numbersAndPunctuation)
            Button(String(localized: "confirm_action")) {
                applyIntegerInput()
            }
            Button(String(localized: "cancel"), role: .cancel) {
                integerSetting = nil
            }
        }
        .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func settingSection(_ setting: APIClient.SystemSettingItem) -> some View {
        if setting.valueType.lowercased() == "string",
           let choiceDescription = choiceDescription(for: setting) {
            Section {
                Picker(
                    choiceDescription.title,
                    selection: stringBinding(for: setting)
                ) {
                    ForEach(choiceDescription.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            }
        } else {
            settingSectionWithoutChoices(setting)
        }
    }

    @ViewBuilder
    private func settingSectionWithoutChoices(
        _ setting: APIClient.SystemSettingItem
    ) -> some View {
        switch setting.valueType.lowercased() {
        case "boolean":
            Section {
                Toggle(
                    localizedDescription(for: setting),
                    isOn: booleanBinding(for: setting)
                )
            }
        case "integer", "long":
            Section {
                Stepper(value: integerBinding(for: setting)) {
                    HStack {
                        Text(localizedDescription(for: setting))
                        Spacer()
                        Button {
                            integerInput = values[setting.key] ?? setting.value
                            integerSetting = setting
                        } label: {
                            Text(values[setting.key] ?? setting.value)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        default:
            Section(localizedDescription(for: setting)) {
                TextField(
                    localizedDescription(for: setting),
                    text: stringBinding(for: setting)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            }
        }
    }

    private func localizedDescription(
        for setting: APIClient.SystemSettingItem?
    ) -> String {
        guard let setting else { return String(localized: "system_settings_integer_value") }
        let isChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        if isChinese {
            return setting.description.zh ?? setting.description.en ?? setting.key
        }
        return setting.description.en ?? setting.description.zh ?? setting.key
    }

    private func choiceDescription(
        for setting: APIClient.SystemSettingItem
    ) -> (title: String, options: [String])? {
        let description = localizedDescription(for: setting)
        let pattern = #"[\(（]([^\(\)（）]*/[^\(\)（）]*/[^\(\)（）]*)[\)）]"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: description,
                range: NSRange(description.startIndex..., in: description)
              ),
              let optionRange = Range(match.range(at: 1), in: description),
              let fullRange = Range(match.range(at: 0), in: description) else {
            return nil
        }

        let options = description[optionRange]
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard options.count >= 3 else { return nil }

        let title = description
            .replacingCharacters(in: fullRange, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let currentValue = values[setting.key] ?? setting.value
        let displayedOptions = options.contains(currentValue)
            ? options
            : options + [currentValue]
        return (title.isEmpty ? setting.key : title, displayedOptions)
    }

    private func stringBinding(for setting: APIClient.SystemSettingItem) -> Binding<String> {
        Binding(
            get: { values[setting.key] ?? setting.value },
            set: { values[setting.key] = $0 }
        )
    }

    private func booleanBinding(for setting: APIClient.SystemSettingItem) -> Binding<Bool> {
        Binding(
            get: { (values[setting.key] ?? setting.value).lowercased() == "true" },
            set: { values[setting.key] = $0 ? "true" : "false" }
        )
    }

    private func integerBinding(for setting: APIClient.SystemSettingItem) -> Binding<Int> {
        Binding(
            get: { Int(values[setting.key] ?? setting.value) ?? 0 },
            set: { values[setting.key] = String($0) }
        )
    }

    private var integerInputAlertPresented: Binding<Bool> {
        Binding(
            get: { integerSetting != nil },
            set: { if !$0 { integerSetting = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func applyIntegerInput() {
        guard let integerSetting else { return }
        guard let integer = Int(integerInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = String(localized: "system_settings_invalid_integer")
            self.integerSetting = nil
            return
        }
        values[integerSetting.key] = String(integer)
        self.integerSetting = nil
    }

    private func save() {
        let updates = changedValues
        guard !updates.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await server.apiClient.updateAdminSystemSettings(updates)
                for (key, value) in updates {
                    savedValues[key] = value
                }
                LogManager.shared.log("[SystemSettings] Saved category=\(category.rawValue) count=\(updates.count)")
            } catch {
                errorMessage = error.localizedDescription
                LogManager.shared.log("[SystemSettings] Save failed: \(error.localizedDescription)")
            }
            isSaving = false
        }
    }
}
