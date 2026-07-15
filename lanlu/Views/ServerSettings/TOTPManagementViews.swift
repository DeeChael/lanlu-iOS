import SwiftUI
import UniformTypeIdentifiers

private struct RecoveryCodesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let codes: [String]

    init(codes: [String]) {
        self.codes = codes
    }

    init(configuration: ReadConfiguration) throws {
        codes = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: codes.joined(separator: "\n").data(using: .utf8) ?? Data())
    }
}

private struct RecoveryCodesView: View {
    let codes: [String]
    let onDone: () -> Void

    @State private var showExporter = false

    var body: some View {
        Form {
            Text("recovery_codes_save_message")
                .listRowBackground(Color.clear)

            Section {
                Grid(horizontalSpacing: 24, verticalSpacing: 10) {
                    ForEach(Array(stride(from: 0, to: codes.count, by: 2)), id: \.self) { index in
                        GridRow {
                            recoveryCode(codes[index])
                            if index + 1 < codes.count {
                                recoveryCode(codes[index + 1])
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    showExporter = true
                } label: {
                    Label(String(localized: "save_recovery_codes"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }

                Button(String(localized: "done")) {
                    onDone()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: RecoveryCodesDocument(codes: codes),
            contentType: .plainText,
            defaultFilename: "lanlu-recovery-codes"
        ) { _ in }
    }

    private func recoveryCode(_ code: String) -> some View {
        Text(code)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

struct TOTPEnrollmentView: View {
    let server: Server
    let onCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var securityPassword = ""
    @State private var showSecurityAlert = false
    @State private var enrollment: TOTPEnrollmentData?
    @State private var verificationCode = ""
    @State private var recoveryCodes: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if !recoveryCodes.isEmpty {
                    RecoveryCodesView(codes: recoveryCodes) {
                        onCompleted()
                        dismiss()
                    }
                } else if let enrollment {
                    enrollmentConfirmation(enrollment)
                } else {
                    nameEntry
                }
            }
            .navigationTitle(String(localized: "add_authenticator"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .alert(String(localized: "security_verification_required"), isPresented: $showSecurityAlert) {
            SecureField(String(localized: "password"), text: $securityPassword)
            Button(String(localized: "cancel"), role: .cancel) {
                securityPassword = ""
            }
            Button(String(localized: "confirm_action")) {
                Task { await startEnrollment() }
            }
            .disabled(securityPassword.isEmpty)
        } message: {
            Text(String(localized: "totp_enrollment_security_message"))
        }
        .interactiveDismissDisabled(isLoading)
    }

    private var nameEntry: some View {
        Form {
            Section {
                TextField(String(localized: "name"), text: $name)
            }
            errorSection
            Section {
                actionButton(String(localized: "confirm_action"), disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    showSecurityAlert = true
                }
            }
        }
    }

    private func enrollmentConfirmation(_ enrollment: TOTPEnrollmentData) -> some View {
        Form {
            Text("totp_enrollment_instructions")
                .listRowBackground(Color.clear)

            Section {
                Button {
                    UIPasteboard.general.string = enrollment.secret
                } label: {
                    Label(String(localized: "copy_secret"), systemImage: "doc.on.doc")
                }

                Button {
                    if let url = URL(string: enrollment.otpauthUri) {
                        openURL(url)
                    }
                } label: {
                    Label(String(localized: "import_authenticator"), systemImage: "arrow.up.forward.app")
                }
            }

            Section {
                TextField(String(localized: "totp_code"), text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)

                actionButton(String(localized: "complete_verification"), disabled: verificationCode.isEmpty) {
                    Task { await confirmEnrollment(enrollment) }
                }
            }

            errorSection
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func actionButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if isLoading { ProgressView() } else { Text(title).fontWeight(.semibold) }
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(disabled || isLoading)
    }

    private func startEnrollment() async {
        isLoading = true
        errorMessage = nil
        do {
            try await server.apiClient.verifyStepUpPassword(securityPassword)
            enrollment = try await server.apiClient.startTOTPEnrollment(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            securityPassword = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func confirmEnrollment(_ enrollment: TOTPEnrollmentData) async {
        isLoading = true
        errorMessage = nil
        do {
            recoveryCodes = try await server.apiClient.confirmTOTPEnrollment(
                challengeId: enrollment.challengeId,
                code: verificationCode,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct TOTPRecoveryResetView: View {
    let server: Server
    let onCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var code = ""
    @State private var recoveryCodes: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if recoveryCodes.isEmpty {
                    Form {
                        Section(String(localized: "password_verification")) {
                            SecureField(String(localized: "password"), text: $password)
                                .textContentType(.password)
                        }
                        Section(String(localized: "totp_verification")) {
                            TextField(String(localized: "totp_code"), text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                        }
                        if let errorMessage {
                            Section {
                                Text(errorMessage).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Section {
                            Button {
                                Task { await resetRecoveryCodes() }
                            } label: {
                                HStack {
                                    if isLoading { ProgressView() } else { Text(String(localized: "reset")).fontWeight(.semibold) }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(password.isEmpty || code.isEmpty || isLoading)
                        }
                    }
                } else {
                    RecoveryCodesView(codes: recoveryCodes) {
                        onCompleted()
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "reset_recovery_codes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").fontWeight(.semibold)
                    }
                    .disabled(isLoading)
                }
            }
        }
        .interactiveDismissDisabled(isLoading)
    }

    private func resetRecoveryCodes() async {
        isLoading = true
        errorMessage = nil
        do {
            try await server.apiClient.verifyStepUpPassword(password)
            recoveryCodes = try await server.apiClient.regenerateTOTPRecoveryCodes(code: code)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
