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
    @State private var totpStatus: TOTPStatusData?
    @State private var isLoadingTOTPStatus = true
    @State private var totpStatusError: String?
    @State private var passkeys: [PasskeyCredential] = []
    @State private var isRefreshingPasskeys = false
    @State private var hasLoadedPasskeys = false
    @State private var passkeyError: String?
    @State private var deletingPasskeyIds: Set<Int> = []
    @State private var loginSessions: [LoginSession] = []
    @State private var isRefreshingLoginSessions = false
    @State private var hasLoadedLoginSessions = false
    @State private var loginSessionError: String?
    @State private var showRevokeOthersAlert = false
    @State private var isRevokingLoginSession = false

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

            Section(String(localized: "totp_section")) {
                if isLoadingTOTPStatus {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let totpStatusError {
                    Text(totpStatusError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let totpStatus, totpStatus.enabled {
                    totpSettingRow(
                        title: String(localized: "totp_enabled"),
                        systemImage: "checkmark.shield",
                        actionTitle: String(localized: "remove"),
                        actionColor: .red
                    )
                } else {
                    totpSettingRow(
                        title: String(localized: "totp_disabled"),
                        systemImage: "shield.slash",
                        actionTitle: String(localized: "add"),
                        actionColor: .accentColor
                    )
                }
            }

            Section {
                if !hasLoadedPasskeys && isRefreshingPasskeys {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                ForEach(passkeys) { credential in
                    HStack {
                        Label(
                            credential.name.isEmpty ? String(localized: "passkey_unnamed") : credential.name,
                            systemImage: "person.badge.key"
                        )
                        Spacer()
                        Text(credential.userVerified ? String(localized: "verified") : String(localized: "unverified"))
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await deletePasskey(credential) }
                        } label: {
                            Label(String(localized: "delete"), systemImage: "trash")
                        }
                        .disabled(deletingPasskeyIds.contains(credential.id))
                    }
                }
                
                if let passkeyError {
                    Text(passkeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {} label: {
                    Label(String(localized: "add_passkey"), systemImage: "plus")
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } header: {
                HStack {
                    Text(String(localized: "passkey_section"))
                    Spacer()
                    Button {
                        Task { await loadPasskeys() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingPasskeys)
                }
            }

            Section {
                Button(role: .destructive) {
                    showRevokeOthersAlert = true
                } label: {
                    Label(String(localized: "sign_out_other_devices"), systemImage: "ipad.landscape.and.iphone.slash")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(isRevokingLoginSession)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                if !hasLoadedLoginSessions && isRefreshingLoginSessions {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }

                ForEach(loginSessions) { session in
                    loginSessionRow(session)
                        .swipeActions(edge: .trailing) {
                            if !session.current {
                                Button(role: .destructive) {
                                    Task { await revokeLoginSession(session) }
                                } label: {
                                    Label(String(localized: "revoke_login"), systemImage: "iphone.slash")
                                }
                                .disabled(isRevokingLoginSession)
                            }
                        }
                }

                if let loginSessionError {
                    Text(loginSessionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                HStack {
                    Text(String(localized: "login_device_management"))
                    Spacer()
                    Button {
                        Task { await loadLoginSessions() }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingLoginSessions)
                }
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
        .alert(String(localized: "sign_out_other_devices"), isPresented: $showRevokeOthersAlert) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "confirm_action"), role: .destructive) {
                Task { await revokeOtherLoginSessions() }
            }
        } message: {
            Text(String(localized: "sign_out_other_devices_confirm"))
        }
        .sheet(isPresented: $showPasswordSheet) {
            PasswordChangeSheet(server: server)
                .presentationDetents([.large])
        }
        .task {
            async let totp: Void = loadTOTPStatus()
            async let passkeys: Void = loadPasskeys()
            async let sessions: Void = loadLoginSessions()
            _ = await (totp, passkeys, sessions)
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

    private func totpSettingRow(
        title: String,
        systemImage: String,
        actionTitle: String,
        actionColor: Color
    ) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(actionTitle)
                .foregroundStyle(actionColor)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func loginSessionRow(_ session: LoginSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(session.name.isEmpty ? String(localized: "unnamed_device") : session.name)
                        .fontWeight(.medium)
                    Text(session.prefix)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay {
                            Capsule().stroke(.secondary, lineWidth: 1)
                        }
                }

                Text(String(format: String(localized: "last_active_format"), relativeSessionDate(session.lastUsedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(format: String(localized: "ip_format"), session.lastUsedIp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if session.current {
                Text("current_device")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay {
                        Capsule().stroke(Color.accentColor, lineWidth: 1)
                    }
            }
        }
        .padding(.vertical, 2)
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

    private func loadTOTPStatus() async {
        isLoadingTOTPStatus = true
        totpStatusError = nil
        do {
            totpStatus = try await server.apiClient.fetchTOTPStatus()
        } catch {
            totpStatusError = error.localizedDescription
        }
        isLoadingTOTPStatus = false
    }

    private func loadPasskeys() async {
        guard !isRefreshingPasskeys else { return }
        isRefreshingPasskeys = true
        passkeyError = nil
        do {
            let refreshedPasskeys = try await server.apiClient.fetchPasskeyCredentials()
            passkeys = refreshedPasskeys
            hasLoadedPasskeys = true
        } catch {
            passkeyError = error.localizedDescription
        }
        isRefreshingPasskeys = false
    }

    private func deletePasskey(_ credential: PasskeyCredential) async {
        guard !deletingPasskeyIds.contains(credential.id) else { return }
        deletingPasskeyIds.insert(credential.id)
        passkeyError = nil
        do {
            try await server.apiClient.deletePasskeyCredential(id: credential.id)
            passkeys.removeAll { $0.id == credential.id }
        } catch {
            passkeyError = error.localizedDescription
        }
        deletingPasskeyIds.remove(credential.id)
    }

    private func loadLoginSessions() async {
        guard !isRefreshingLoginSessions else { return }
        isRefreshingLoginSessions = true
        loginSessionError = nil
        do {
            let refreshedSessions = try await server.apiClient.fetchLoginSessions()
            loginSessions = refreshedSessions
            hasLoadedLoginSessions = true
        } catch {
            loginSessionError = error.localizedDescription
        }
        isRefreshingLoginSessions = false
    }

    private func revokeOtherLoginSessions() async {
        guard !isRevokingLoginSession else { return }
        isRevokingLoginSession = true
        loginSessionError = nil
        do {
            try await server.apiClient.revokeOtherLoginSessions()
            loginSessions.removeAll { !$0.current }
        } catch {
            loginSessionError = error.localizedDescription
        }
        isRevokingLoginSession = false
    }

    private func revokeLoginSession(_ session: LoginSession) async {
        guard !isRevokingLoginSession else { return }
        isRevokingLoginSession = true
        loginSessionError = nil
        do {
            try await server.apiClient.revokeLoginSession(id: session.id)
            loginSessions.removeAll { $0.id == session.id }
        } catch {
            loginSessionError = error.localizedDescription
        }
        isRevokingLoginSession = false
    }

    private func relativeSessionDate(_ value: String) -> String {
        guard let date = sessionDate(from: value) else { return value }

        let now = Date()
        let interval = max(0, now.timeIntervalSince(date))
        let calendar = Calendar.current

        if interval < 60 {
            return String(localized: "just_now")
        }
        if interval < 60 * 60 {
            return String(format: String(localized: "minutes_ago"), Int(interval / 60))
        }
        if calendar.isDateInToday(date) {
            return String(format: String(localized: "hours_ago"), max(1, Int(interval / 3600)))
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "yesterday")
        }
        if let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           daysAgo == 2 {
            return String(localized: "day_before_yesterday")
        }
        if let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day,
           daysAgo < 7 {
            return String(format: String(localized: "days_ago"), daysAgo)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(date, equalTo: now, toGranularity: .year) ? "Md" : "yMd"
        )
        return formatter.string(from: date)
    }

    private func sessionDate(from value: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss.SSSSSS", "yyyy-MM-dd HH:mm:ss"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
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
