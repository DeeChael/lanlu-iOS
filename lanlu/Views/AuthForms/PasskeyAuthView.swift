import SwiftUI

struct PasskeyAuthView: View {
    let serverName: String
    let serverURL: String
    let onSave: (String?) -> Void

    private let client: APIClient
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
                Label(String(localized: "passkey_login_description"), systemImage: "person.badge.key.fill")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await authenticate() }
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        else { Text(String(localized: "login_with_passkey")).fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle(String(localized: "passkey"))
    }

    private func authenticate() async {
        isLoading = true
        errorMessage = nil
        do {
            let options = try await client.fetchWebAuthnAuthenticationOptions()
            let credential = try await WebAuthnService.shared.authenticate(options: options.publicKey)
            let result = try await client.verifyWebAuthnAuthentication(
                challengeId: options.challengeId,
                credential: credential
            )
            let auth = ["token": result.token.token ?? ""]
            let data = try JSONEncoder().encode(auth)
            onSave(String(data: data, encoding: .utf8))
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
