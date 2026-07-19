import SwiftUI

struct UserManagementView: View {
    private enum SheetRoute: Identifiable {
        case create
        case resetPassword(AdminUser)

        var id: String {
            switch self {
            case .create: "create"
            case .resetPassword(let user): "reset-\(user.id)"
            }
        }
    }

    let server: Server

    @State private var users: [AdminUser] = []
    @State private var adminStates: [Int: Bool] = [:]
    @State private var updatingRoleIds: Set<Int> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sheetRoute: SheetRoute?
    @State private var userPendingDeletion: AdminUser?

    var body: some View {
        List {
            if isLoading && users.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }

            ForEach(users) { user in
                userRow(user)
                    .swipeActions(
                        edge: .trailing,
                        allowsFullSwipe: false
                    ) {
                        if !isCurrentUser(user) {
                            Button(role: .destructive) {
                                userPendingDeletion = user
                            } label: {
                                Image(systemName: "trash")
                            }

                            Button {
                                sheetRoute = .resetPassword(user)
                            } label: {
                                Image(systemName: "key.horizontal")
                            }
                            .tint(.accentColor)
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    sheetRoute = .create
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .create:
                CreateUserView(server: server) {
                    Task { await loadUsers() }
                }
                .presentationDetents([.large])
            case .resetPassword(let user):
                ResetUserPasswordView(server: server, user: user)
                    .presentationDetents([.large])
            }
        }
        .alert(
            String(localized: "user_delete_title"),
            isPresented: deleteAlertPresented,
            presenting: userPendingDeletion
        ) { user in
            Button(String(localized: "delete"), role: .destructive) {
                deleteUser(user)
            }
            Button(String(localized: "cancel"), role: .cancel) {}
        } message: { user in
            Text(
                String(
                    format: String(localized: "user_delete_confirm"),
                    user.username
                )
            )
        }
        .alert(
            String(localized: "error_title"),
            isPresented: errorAlertPresented
        ) {
            Button(String(localized: "ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadUsers()
        }
    }

    private func userRow(_ user: AdminUser) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.username)
                        .fontWeight(.medium)
                    adminBadge(isAdmin: adminStates[user.id] ?? user.isAdmin)
                }

                Text(
                    String(
                        format: String(localized: "user_created_time"),
                        formattedCreatedAt(user.createdAt)
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(String(localized: "administrator"))
                .font(.subheadline)
            Toggle("", isOn: adminBinding(for: user))
                .labelsHidden()
                .disabled(isCurrentUser(user) || updatingRoleIds.contains(user.id))
        }
        .padding(.vertical, 3)
    }

    private func adminBadge(isAdmin: Bool) -> some View {
        Text(String(localized: isAdmin ? "user_admin" : "user_regular"))
            .font(.caption2)
            .foregroundStyle(isAdmin ? Color.accentColor : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay {
                Capsule()
                    .stroke(isAdmin ? Color.accentColor : Color.primary, lineWidth: 1)
            }
    }

    private func isCurrentUser(_ user: AdminUser) -> Bool {
        user.username == server.cachedUsername
    }

    private func adminBinding(for user: AdminUser) -> Binding<Bool> {
        Binding(
            get: { adminStates[user.id] ?? user.isAdmin },
            set: { updateRole(user, isAdmin: $0) }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { userPendingDeletion != nil },
            set: { if !$0 { userPendingDeletion = nil } }
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func loadUsers() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedUsers = try await server.apiClient.fetchAdminUsers()
            users = loadedUsers
            adminStates = Dictionary(
                uniqueKeysWithValues: loadedUsers.map { ($0.id, $0.isAdmin) }
            )
            LogManager.shared.log("[Users] Load completed count=\(loadedUsers.count)")
        } catch {
            errorMessage = error.localizedDescription
            LogManager.shared.log("[Users] Load failed: \(error.localizedDescription)")
        }
        isLoading = false
    }

    private func updateRole(_ user: AdminUser, isAdmin: Bool) {
        guard !isCurrentUser(user), !updatingRoleIds.contains(user.id) else { return }
        let previousValue = adminStates[user.id] ?? user.isAdmin
        adminStates[user.id] = isAdmin
        updatingRoleIds.insert(user.id)

        Task {
            do {
                try await server.apiClient.updateAdminUserRole(
                    id: user.id,
                    isAdmin: isAdmin
                )
                LogManager.shared.log("[Users] Role updated id=\(user.id) admin=\(isAdmin)")
            } catch {
                adminStates[user.id] = previousValue
                errorMessage = error.localizedDescription
                LogManager.shared.log("[Users] Role update failed: \(error.localizedDescription)")
            }
            updatingRoleIds.remove(user.id)
        }
    }

    private func deleteUser(_ user: AdminUser) {
        Task {
            do {
                try await server.apiClient.deleteAdminUser(id: user.id)
                users.removeAll { $0.id == user.id }
                adminStates.removeValue(forKey: user.id)
                LogManager.shared.log("[Users] Deleted id=\(user.id)")
            } catch {
                errorMessage = error.localizedDescription
                LogManager.shared.log("[Users] Delete failed: \(error.localizedDescription)")
            }
        }
    }

    private func formattedCreatedAt(_ value: String) -> String {
        let fractionalFormatter = DateFormatter()
        fractionalFormatter.locale = Locale(identifier: "en_US_POSIX")
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        fractionalFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        let standardFormatter = ISO8601DateFormatter()
        standardFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let date = standardFormatter.date(from: value)
            ?? fractionalFormatter.date(from: value)
        guard let date else { return value }

        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.timeZone = .current
        output.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return output.string(from: date)
    }
}

private struct CreateUserView: View {
    let server: Server
    let onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isAdmin = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "username"), text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Toggle(String(localized: "set_as_administrator"), isOn: $isAdmin)
                }
                Section {
                    Button {
                        createUser()
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView() }
                            Text(String(localized: "create"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                }
            }
            .navigationTitle(String(localized: "create_user"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
                Button(String(localized: "ok")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func createUser() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await server.apiClient.createAdminUser(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    isAdmin: isAdmin
                )
                onCreated()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

private struct ResetUserPasswordView: View {
    let server: Server
    let user: AdminUser

    @Environment(\.dismiss) private var dismiss
    @State private var newPassword = ""
    @State private var confirmedPassword = ""
    @State private var showsNewPassword = false
    @State private var verificationPassword = ""
    @State private var showsVerificationPassword = false
    @State private var needsStepUp = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if needsStepUp {
                    Section(String(localized: "password_verification")) {
                        HStack {
                            Group {
                                if showsVerificationPassword {
                                    TextField(String(localized: "password"), text: $verificationPassword)
                                } else {
                                    SecureField(String(localized: "password"), text: $verificationPassword)
                                }
                            }
                            .textContentType(.password)

                            Button {
                                showsVerificationPassword.toggle()
                            } label: {
                                Image(systemName: showsVerificationPassword ? "eye.fill" : "eye.slash.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                String(localized: showsVerificationPassword ? "hide_password" : "show_password")
                            )
                        }
                    }
                } else {
                    Section {
                        HStack {
                            Group {
                                if showsNewPassword {
                                    TextField(String(localized: "new_password"), text: $newPassword)
                                } else {
                                    SecureField(String(localized: "new_password"), text: $newPassword)
                                }
                            }
                            .textContentType(.newPassword)

                            passwordVisibilityButton(isVisible: $showsNewPassword)
                        }

                        HStack {
                            Group {
                                if showsNewPassword {
                                    TextField(String(localized: "confirm_new_password"), text: $confirmedPassword)
                                } else {
                                    SecureField(String(localized: "confirm_new_password"), text: $confirmedPassword)
                                }
                            }
                            .textContentType(.newPassword)
                        }
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView() }
                            Text(String(localized: needsStepUp ? "verify" : "confirm_action"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(submitDisabled)
                }
            }
            .navigationTitle(
                String(localized: needsStepUp ? "step_up_verification" : "change_user_password")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                }
            }
            .alert(String(localized: "error_title"), isPresented: errorAlertPresented) {
                Button(String(localized: "ok")) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var submitDisabled: Bool {
        if isSubmitting { return true }
        return needsStepUp
            ? verificationPassword.isEmpty
            : newPassword.isEmpty || confirmedPassword.isEmpty
    }

    private func passwordVisibilityButton(isVisible: Binding<Bool>) -> some View {
        Button {
            isVisible.wrappedValue.toggle()
        } label: {
            Image(systemName: isVisible.wrappedValue ? "eye.fill" : "eye.slash.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            String(localized: isVisible.wrappedValue ? "hide_password" : "show_password")
        )
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func submit() {
        guard !submitDisabled else { return }
        guard needsStepUp || newPassword == confirmedPassword else {
            errorMessage = String(localized: "passwords_do_not_match")
            return
        }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                if !needsStepUp {
                    needsStepUp = true
                    isSubmitting = false
                    return
                }
                try await server.apiClient.verifyStepUpPassword(verificationPassword)
                try await server.apiClient.resetAdminUserPassword(
                    id: user.id,
                    newPassword: newPassword
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
