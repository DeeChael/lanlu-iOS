import SwiftUI

struct PasswordAuthView: View {
    let serverName: String
    let serverURL: String
    let onSave: (String?) -> Void

    private let client: APIClient

    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var challengeId: String?
    @State private var totpCode = ""

    init(serverName: String, serverURL: String, onSave: @escaping (String?) -> Void) {
        self.serverName = serverName
        self.serverURL = serverURL
        self.onSave = onSave
        self.client = APIClient(baseURL: serverURL)
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "username"), text: $username)
                    .textContentType(.username)
                    .disabled(isLoading)

                HStack {
                    if showPassword {
                        TextField(String(localized: "password"), text: $password)
                            .textContentType(.password)
                    } else {
                        SecureField(String(localized: "password"), text: $password)
                            .textContentType(.password)
                    }
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .disabled(isLoading)
            }

            if let challengeId {
                Section(String(localized: "totp_title")) {
                    TextField(String(localized: "totp_code"), text: $totpCode)
                        .keyboardType(.numberPad)
                        .disabled(isLoading)
                }
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
                    Task { await performLogin() }
                } label: {
                    HStack {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text(String(localized: "save"))
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(canSave == false || isLoading)
            }
        }
        .navigationTitle(String(localized: "account_password"))
    }

    private var canSave: Bool {
        if challengeId != nil {
            return !totpCode.isEmpty
        }
        return !username.isEmpty && !password.isEmpty
    }

    private func performLogin() async {
        isLoading = true
        errorMessage = nil

        if let challengeId {
            do {
                let result = try await client.verifyTOTP(challengeId: challengeId, code: totpCode)
                let data = [
                    "username": username,
                    "password": password,
                    "token": result.token.token ?? ""
                ]
                if let jsonData = try? JSONEncoder().encode(data) {
                    onSave(String(data: jsonData, encoding: .utf8))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            do {
                let result = try await client.login(username: username, password: password)
                let data = [
                    "username": username,
                    "password": password,
                    "token": result.token.token ?? ""
                ]
                if let jsonData = try? JSONEncoder().encode(data) {
                    onSave(String(data: jsonData, encoding: .utf8))
                }
            } catch AuthError.totpRequired(let cId, _) {
                self.challengeId = cId
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}
