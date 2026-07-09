import SwiftUI
import SwiftData

enum AuthMethod: String, CaseIterable {
    case password
    case token
    case passkey

    var icon: String {
        switch self {
        case .password: "person.fill"
        case .token: "key.fill"
        case .passkey: "lock.fill"
        }
    }

    var title: String {
        switch self {
        case .password: String(localized: "account_password")
        case .token: String(localized: "token")
        case .passkey: String(localized: "passkey")
        }
    }
}

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let existingServer: Server?

    @State private var name: String
    @State private var baseURL: String
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var step: AddServerStep = .input

    init(existingServer: Server? = nil) {
        self.existingServer = existingServer
        _name = State(initialValue: existingServer?.name ?? "")
        _baseURL = State(initialValue: existingServer?.baseURL ?? "")
    }

    enum AddServerStep: Equatable {
        case input
        case authMethod
        case authForm(AuthMethod)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .input:
                    inputView
                case .authMethod:
                    authMethodPicker
                case .authForm(let method):
                    authForm(for: method)
                }
            }
            .navigationTitle(String(localized: existingServer != nil ? "edit_server" : "add_server_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .input {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(String(localized: "back")) {
                            withAnimation { goBack() }
                        }
                    }
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
        }
    }

    private var inputView: some View {
        Form {
            Section {
                TextField(String(localized: "server_name"), text: $name)

                TextField(String(localized: "server_url"), text: $baseURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(String(localized: "connect"))
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(name.isEmpty || baseURL.isEmpty || isLoading)
            }
        }
    }

    private var authMethodPicker: some View {
        List {
            Section {
                ForEach(AuthMethod.allCases, id: \.self) { method in
                    Button {
                        withAnimation { step = .authForm(method) }
                    } label: {
                        Label(method.title, systemImage: method.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(method == .passkey)
                }
            } header: {
                Text(String(localized: "choose_auth_method"))
            } footer: {
                Text("passkey_unavailable")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func authForm(for method: AuthMethod) -> some View {
        switch method {
        case .password:
            PasswordAuthView(serverName: name, serverURL: baseURL, onSave: { saveServer(method: method, authData: $0) })
        case .token:
            TokenAuthView(serverName: name, serverURL: baseURL, onSave: { saveServer(method: method, authData: $0) })
        case .passkey:
            PasskeyAuthView(serverName: name, serverURL: baseURL, onSave: { saveServer(method: method, authData: $0) })
        }
    }

    private func goBack() {
        switch step {
        case .authMethod:
            step = .input
        case .authForm:
            step = .authMethod
        default:
            break
        }
    }

    private func testConnection() async {
        isLoading = true
        errorMessage = nil

        do {
            _ = try await NetworkService.shared.testConnection(baseURL: baseURL)
            withAnimation { step = .authMethod }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func saveServer(method: AuthMethod, authData: String?) {
        if let existingServer {
            existingServer.name = name
            existingServer.baseURL = baseURL
            existingServer.authMethod = method.rawValue
            existingServer.authData = authData
            existingServer.lastUsedAt = Date()
        } else {
            let server = Server(name: name, baseURL: baseURL, authMethod: method.rawValue, authData: authData)
            server.lastUsedAt = Date()
            modelContext.insert(server)
        }
        try? modelContext.save()
        dismiss()
    }
}
