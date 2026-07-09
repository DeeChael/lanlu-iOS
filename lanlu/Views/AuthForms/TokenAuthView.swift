import SwiftUI

struct TokenAuthView: View {
    let serverName: String
    let serverURL: String
    let onSave: (String?) -> Void

    private let client: APIClient

    @State private var token = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(serverName: String, serverURL: String, onSave: @escaping (String?) -> Void) {
        self.serverName = serverName
        self.serverURL = serverURL
        self.onSave = onSave
        self.client = APIClient(baseURL: serverURL)
    }

    var body: some View {
        Form {
            Section {
                SecureField("Token", text: $token)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .disabled(isLoading)
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
                    Task { await performVerify() }
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
                .disabled(token.isEmpty || isLoading)
            }
        }
        .navigationTitle(String(localized: "token"))
    }

    private func performVerify() async {
        isLoading = true
        errorMessage = nil

        client.token = token

        do {
            _ = try await client.verifyToken()
            let data = ["token": token]
            if let jsonData = try? JSONEncoder().encode(data) {
                onSave(String(data: jsonData, encoding: .utf8))
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
