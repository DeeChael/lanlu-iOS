import SwiftUI
import ImageIO
import UIKit

private enum ManagedPluginType: String, CaseIterable, Identifiable {
    case all = ""
    case metadata = "Metadata"
    case download = "Download"
    case login = "Login"
    case script = "Script"
    case source = "Source"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "plugin_type_all")
        case .metadata: String(localized: "plugin_type_metadata")
        case .download: String(localized: "plugin_type_download")
        case .login: String(localized: "plugin_type_login")
        case .script: String(localized: "plugin_type_script")
        case .source: String(localized: "plugin_type_source")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .metadata: "info.square"
        case .download: "square.and.arrow.down"
        case .login: "ipad.and.arrow.forward"
        case .script: "document"
        case .source: "cloud"
        }
    }

    var color: Color {
        switch self {
        case .all: .primary
        case .metadata: .blue
        case .download: .green
        case .login: .purple
        case .script: .orange
        case .source: .indigo
        }
    }
}

struct PluginManagementView: View {
    let server: Server

    @State private var plugins: [APIClient.AdminPlugin] = []
    @State private var selectedType: ManagedPluginType = .all
    @State private var expandedNamespaces: Set<String> = []
    @State private var enabledStates: [String: Bool] = [:]
    @State private var changingNamespaces: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var installURL = ""
    @State private var showInstallAlert = false
    @State private var isInstalling = false
    @State private var configurationPlugin: APIClient.AdminPlugin?
    @State private var pluginPendingDeletion: APIClient.AdminPlugin?

    private var visiblePlugins: [APIClient.AdminPlugin] {
        guard selectedType != .all else { return plugins }
        return plugins.filter {
            $0.pluginType?.caseInsensitiveCompare(selectedType.rawValue) == .orderedSame
        }
    }

    var body: some View {
        List {
            if isLoading && plugins.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            ForEach(visiblePlugins) { plugin in
                PluginManagementRow(
                    plugin: plugin,
                    enabled: enabledBinding(for: plugin),
                    expanded: expandedNamespaces.contains(plugin.namespace),
                    isChanging: changingNamespaces.contains(plugin.namespace),
                    onToggleExpanded: { toggleExpanded(plugin) }
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pluginPendingDeletion = plugin
                    } label: {
                        Image(systemName: "trash")
                    }
                    if hasParameters(plugin) {
                        Button {
                            configurationPlugin = plugin
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            Picker("", selection: $selectedType) {
                ForEach(ManagedPluginType.allCases) { type in
                    Image(systemName: type.systemImage)
                        .accessibilityLabel(type.title)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    installURL = ""
                    showInstallAlert = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .alert(String(localized: "plugin_install_title"), isPresented: $showInstallAlert) {
            TextField(String(localized: "plugin_url"), text: $installURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "confirm_action")) {
                installPlugin()
            }
            .disabled(installURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            String(localized: "plugin_delete_title"),
            isPresented: deleteAlertPresented,
            presenting: pluginPendingDeletion
        ) { plugin in
            Button(String(localized: "delete"), role: .destructive) {
                deletePlugin(plugin)
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: { plugin in
            Text(String(format: String(localized: "plugin_delete_confirm"), plugin.name))
        }
        .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $configurationPlugin) { plugin in
            PluginConfigurationView(plugin: plugin)
                .presentationDetents([.large])
        }
        .task {
            await loadPlugins()
        }
    }

    private func hasParameters(_ plugin: APIClient.AdminPlugin) -> Bool {
        !(plugin.parameters ?? []).isEmpty
    }

    private func enabledBinding(for plugin: APIClient.AdminPlugin) -> Binding<Bool> {
        Binding(
            get: { enabledStates[plugin.namespace] ?? plugin.enabled ?? false },
            set: { updateEnabled($0, for: plugin) }
        )
    }

    private func toggleExpanded(_ plugin: APIClient.AdminPlugin) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if expandedNamespaces.contains(plugin.namespace) {
                expandedNamespaces.remove(plugin.namespace)
            } else {
                expandedNamespaces.insert(plugin.namespace)
            }
        }
    }

    private func loadPlugins() async {
        isLoading = true
        do {
            let loaded = try await server.apiClient.fetchAdminPlugins()
            plugins = loaded
            enabledStates = Dictionary(
                uniqueKeysWithValues: loaded.map {
                    ($0.namespace, $0.enabled ?? false)
                }
            )
            LogManager.shared.log("[Plugins] Load completed count=\(loaded.count)")
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[Plugins] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func updateEnabled(_ enabled: Bool, for plugin: APIClient.AdminPlugin) {
        guard !changingNamespaces.contains(plugin.namespace) else { return }
        let previous = enabledStates[plugin.namespace] ?? plugin.enabled ?? false
        enabledStates[plugin.namespace] = enabled
        changingNamespaces.insert(plugin.namespace)
        Task {
            do {
                try await server.apiClient.setAdminPluginEnabled(
                    namespace: plugin.namespace,
                    enabled: enabled
                )
            } catch {
                enabledStates[plugin.namespace] = previous
                errorMessage = error.localizedDescription
            }
            changingNamespaces.remove(plugin.namespace)
        }
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { pluginPendingDeletion != nil },
            set: { if !$0 { pluginPendingDeletion = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func installPlugin() {
        let url = installURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        isInstalling = true
        Task {
            do {
                try await server.apiClient.installAdminPlugin(url: url)
                await loadPlugins()
            } catch {
                errorMessage = error.localizedDescription
            }
            isInstalling = false
        }
    }

    private func deletePlugin(_ plugin: APIClient.AdminPlugin) {
        Task {
            do {
                try await server.apiClient.deleteAdminPlugin(namespace: plugin.namespace)
                plugins.removeAll { $0.namespace == plugin.namespace }
                enabledStates.removeValue(forKey: plugin.namespace)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PluginManagementRow: View {
    let plugin: APIClient.AdminPlugin
    @Binding var enabled: Bool
    let expanded: Bool
    let isChanging: Bool
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 10) {
                        pluginIcon
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(plugin.name).fontWeight(.medium)
                                typeBadge
                            }
                            Text("\(String(localized: "plugin_namespace"))：\(plugin.namespace)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(localized: "plugin_author"))：\(plugin.author ?? "-")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(String(localized: "plugin_version"))：\(plugin.version ?? "-")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: expanded ? "chevron.down" : "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .disabled(isChanging)
            }

            if expanded {
                expandedDetails
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggleExpanded)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 5)
        .animation(.easeInOut(duration: 0.22), value: expanded)
    }

    private var pluginIcon: some View {
        Group {
            if let icon = plugin.icon,
               !icon.isEmpty,
               let url = URL(string: icon) {
                RemotePluginIcon(url: url)
            } else {
                placeholderIcon
            }
        }
        .frame(width: 34, height: 34)
    }

    private var placeholderIcon: some View {
        Image(systemName: "shippingbox")
            .font(.title3)
            .foregroundStyle(.secondary)
    }

    private var typeBadge: some View {
        let type = ManagedPluginType(rawValue: plugin.pluginType ?? "") ?? .all
        return Text(type.title)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(type.color)
            .clipShape(Capsule())
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let description = plugin.description, !description.isEmpty {
                Text("\(String(localized: "plugin_description"))：")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let permissions = plugin.permissions, !permissions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(String(localized: "plugin_permissions"))：")
                        .font(.caption)
                    FlowLayout(spacing: 5) {
                        ForEach(permissions, id: \.self) { permission in
                            Text(permission)
                                .font(.caption2)
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.leading, 44)
    }
}

private struct RemotePluginIcon: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "shippingbox")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else { return }

        if let decoded = UIImage(data: data) {
            image = decoded
            return
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        image = UIImage(cgImage: cgImage)
    }
}

private struct PluginConfigurationView: View {
    let plugin: APIClient.AdminPlugin
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String]
    @State private var showPendingAlert = false

    init(plugin: APIClient.AdminPlugin) {
        self.plugin = plugin
        _values = State(initialValue: Dictionary(
            uniqueKeysWithValues: (plugin.parameters ?? []).map {
                ($0.name, $0.value ?? $0.defaultValue ?? ($0.type.lowercased() == "bool" ? "0" : ""))
            }
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(plugin.parameters ?? []) { parameter in
                    parameterView(parameter)
                }
            }
            .navigationTitle(String(localized: "plugin_configure"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .confirm) { showPendingAlert = true } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                    .disabled(!isChanged)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            .alert(String(localized: "plugin_config_pending_title"), isPresented: $showPendingAlert) {
                Button(String(localized: "ok")) { showPendingAlert = false }
            } message: {
                Text(String(localized: "plugin_config_pending_message"))
            }
        }
    }

    private var isChanged: Bool {
        (plugin.parameters ?? []).contains {
            values[$0.name] != ($0.value ?? $0.defaultValue ?? ($0.type.lowercased() == "bool" ? "0" : ""))
        }
    }

    @ViewBuilder
    private func parameterView(_ parameter: APIClient.AdminPluginParameter) -> some View {
        let type = parameter.type.lowercased()
        if type == "bool" {
            Section {
                Toggle(parameter.desc, isOn: boolBinding(parameter))
            }
        } else {
            Section(parameter.desc) {
                TextField(
                    parameter.name,
                    text: stringBinding(parameter),
                    prompt: Text(parameter.defaultValue ?? "")
                )
                .keyboardType(type == "int" || type == "number" ? .numbersAndPunctuation : .default)
            }
        }
    }

    private func stringBinding(_ parameter: APIClient.AdminPluginParameter) -> Binding<String> {
        Binding(
            get: { values[parameter.name] ?? "" },
            set: { values[parameter.name] = $0 }
        )
    }

    private func boolBinding(_ parameter: APIClient.AdminPluginParameter) -> Binding<Bool> {
        Binding(
            get: { values[parameter.name] == "1" },
            set: { values[parameter.name] = $0 ? "1" : "0" }
        )
    }
}
