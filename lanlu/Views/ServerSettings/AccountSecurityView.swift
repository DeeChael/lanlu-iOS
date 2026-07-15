import SwiftUI
import SwiftData

struct AccountSecurityView: View {
    let server: Server

    @Environment(\.modelContext) private var modelContext
    @State private var showUsernamePrompt = false
    @State private var showPasswordSheet = false
    @State private var username = ""
    @State private var isChangingUsername = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        List {
            Section(String(localized: "account_credentials")) {
                Button {
                    username = server.cachedUsername ?? ""
                    showUsernamePrompt = true
                } label: {
                    settingRow(
                        title: String(localized: "change_username"),
                        systemImage: "pencil.line"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showPasswordSheet = true
                } label: {
                    settingRow(
                        title: String(localized: "change_password"),
                        systemImage: "key"
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .alert(String(localized: "change_username"), isPresented: $showUsernamePrompt) {
            TextField(String(localized: "new_username"), text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "confirm_action"), role: .confirm) {
                Task { await changeUsername() }
            }
            .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isChangingUsername)
        }
        .alert(String(localized: "operation_failed"), isPresented: $showError) {
            Button(String(localized: "ok")) {}
        } message: {
            Text(errorMessage ?? String(localized: "connection_failed"))
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordChangeSheet(server: server)
                .presentationDetents([.large])
        }
    }

    private func settingRow(title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func changeUsername() async {
        let newUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newUsername.isEmpty else { return }

        isChangingUsername = true
        do {
            let user = try await server.apiClient.changeUsername(newUsername)
            server.cachedUsername = user.username
            server.cachedAvatarAssetId = user.avatarAssetId
            server.cachedIsAdmin = user.isAdmin
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isChangingUsername = false
    }
}

private enum PasswordChangeDestination: Hashable {
    case stepUpOptions
    case passwordVerification
    case totpVerification
}

private struct PasswordChangeSheet: View {
    let server: Server

    @Environment(\.dismiss) private var dismiss
    @State private var path: [PasswordChangeDestination] = []
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmedPassword = ""
    @State private var verificationPassword = ""
    @State private var totpCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            passwordForm
                .navigationDestination(for: PasswordChangeDestination.self) { destination in
                    switch destination {
                    case .stepUpOptions:
                        stepUpOptions
                    case .passwordVerification:
                        passwordVerification
                    case .totpVerification:
                        totpVerification
                    }
                }
                .navigationTitle(String(localized: "change_password"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { closeToolbar }
        }
    }

    private var passwordForm: some View {
        Form {
            Section(String(localized: "current_password")) {
                SecureField(String(localized: "current_password"), text: $currentPassword)
                    .textContentType(.password)
            }

            Section(String(localized: "new_password")) {
                SecureField(String(localized: "new_password"), text: $newPassword)
                    .textContentType(.newPassword)
                SecureField(String(localized: "confirm_new_password"), text: $confirmedPassword)
                    .textContentType(.newPassword)
            }

            errorSection

            Section {
                submitButton(String(localized: "confirm_action"), disabled: passwordFieldsAreEmpty) {
                    guard newPassword == confirmedPassword else {
                        throw AuthError.networkError(String(localized: "passwords_do_not_match"))
                    }
                    let result = try await server.apiClient.changePassword(
                        currentPassword: currentPassword,
                        newPassword: newPassword
                    )
                    handlePasswordChangeResult(result)
                }
            }
        }
    }

    private var stepUpOptions: some View {
        List {
            Section {
                NavigationLink(value: PasswordChangeDestination.passwordVerification) {
                    Label(String(localized: "password_verification"), systemImage: "key.fill")
                }
                NavigationLink(value: PasswordChangeDestination.totpVerification) {
                    Label(String(localized: "totp_verification"), systemImage: "number.square.fill")
                }
            } footer: {
                Text("step_up_required_message")
            }
        }
        .navigationTitle(String(localized: "step_up_verification"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { closeToolbar }
    }

    private var passwordVerification: some View {
        Form {
            Section(String(localized: "password_verification")) {
                SecureField(String(localized: "password"), text: $verificationPassword)
                    .textContentType(.password)
            }
            errorSection
            Section {
                submitButton(String(localized: "verify"), disabled: verificationPassword.isEmpty) {
                    try await server.apiClient.verifyStepUpPassword(verificationPassword)
                    try await retryPasswordChange()
                }
            }
        }
        .navigationTitle(String(localized: "password_verification"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { closeToolbar }
    }

    private var totpVerification: some View {
        Form {
            Section(String(localized: "totp_verification")) {
                TextField(String(localized: "totp_code"), text: $totpCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }
            errorSection
            Section {
                submitButton(String(localized: "verify"), disabled: totpCode.isEmpty) {
                    try await server.apiClient.verifyStepUpTOTP(totpCode)
                    try await retryPasswordChange()
                }
            }
        }
        .navigationTitle(String(localized: "totp_verification"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { closeToolbar }
    }

    @ToolbarContentBuilder
    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel(String(localized: "cancel"))
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var passwordFieldsAreEmpty: Bool {
        currentPassword.isEmpty || newPassword.isEmpty || confirmedPassword.isEmpty
    }

    private func submitButton(
        _ title: String,
        disabled: Bool,
        action: @escaping () async throws -> Void
    ) -> some View {
        Button {
            Task { await perform(action) }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(disabled || isLoading)
    }

    private func retryPasswordChange() async throws {
        let result = try await server.apiClient.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
        handlePasswordChangeResult(result)
    }

    private func handlePasswordChangeResult(_ result: PasswordChangeResult) {
        switch result {
        case .changed:
            NotificationCenter.default.post(name: .serverCredentialsUpdated, object: server)
            dismiss()
        case .requiresStepUp:
            errorMessage = nil
            path = [.stepUpOptions]
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
