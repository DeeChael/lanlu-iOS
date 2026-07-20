import SwiftUI

struct StepUpVerificationSheet: View {
    let server: Server
    let onVerified: () async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var methods: [String] = []
    @State private var selectedMethod: String?
    @State private var password = ""
    @State private var code = ""
    @State private var useRecoveryCode = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if isLoading && methods.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if selectedMethod == nil {
                    Section {
                        if methods.contains("password") {
                            methodButton("password", "password_verification", "key.fill")
                        }
                        if methods.contains("totp") {
                            methodButton("totp", "totp_verification", "number.square.fill")
                        }
                        if methods.contains("passkey") {
                            methodButton("passkey", "passkey_verification", "person.badge.key.fill")
                        }
                    }
                } else if selectedMethod == "password" {
                    Section(String(localized: "password_verification")) {
                        SecureField(String(localized: "password"), text: $password)
                    }
                    submitButton(disabled: password.isEmpty) {
                        try await server.apiClient.verifyStepUpPassword(password)
                    }
                } else if selectedMethod == "totp" {
                    Section(String(localized: "totp_verification")) {
                        TextField(
                            String(localized: useRecoveryCode ? "recovery_code" : "totp_code"),
                            text: $code
                        )
                        .keyboardType(useRecoveryCode ? .asciiCapable : .numberPad)
                        Button(String(localized: useRecoveryCode ? "use_verification_code" : "use_recovery_code")) {
                            useRecoveryCode.toggle()
                            code = ""
                        }
                    }
                    submitButton(disabled: code.isEmpty) {
                        if useRecoveryCode {
                            try await server.apiClient.verifyStepUpTOTP(recoveryCode: code)
                        } else {
                            try await server.apiClient.verifyStepUpTOTP(code: code)
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(String(localized: "step_up_verification"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .task { await loadMethods() }
        }
    }

    private func methodButton(_ method: String, _ title: LocalizedStringKey, _ icon: String) -> some View {
        Button {
            if method == "passkey" {
                Task { await verifyPasskey() }
            } else {
                selectedMethod = method
            }
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(isLoading)
    }

    @ViewBuilder
    private func submitButton(
        disabled: Bool,
        verification: @escaping () async throws -> Void
    ) -> some View {
        Section {
            Button { Task { await complete(verification) } } label: {
                HStack {
                    if isLoading { ProgressView() }
                    else { Text(String(localized: "verify")).fontWeight(.semibold) }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(disabled || isLoading)
        }
    }

    private func loadMethods() async {
        do {
            methods = try await server.apiClient.fetchStepUpMethods()
            if methods.isEmpty { errorMessage = String(localized: "no_step_up_methods") }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func verifyPasskey() async {
        await complete {
            let options = try await server.apiClient.fetchWebAuthnStepUpOptions()
            let assertion = try await WebAuthnService.shared.authenticate(options: options.publicKey)
            try await server.apiClient.verifyWebAuthnStepUp(
                challengeId: options.challengeId,
                credential: assertion
            )
        }
    }

    private func complete(_ verification: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await verification()
            try await onVerified()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}
