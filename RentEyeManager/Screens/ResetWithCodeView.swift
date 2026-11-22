import SwiftUI

/// "Have a reset code?": a tenant without email sets a new password with the code their landlord sent them.
struct ResetWithCodeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var prefill: String = ""

    @State private var emailOrPhone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var done = false

    private var canSave: Bool {
        !emailOrPhone.trimmingCharacters(in: .whitespaces).isEmpty
            && code.filter { $0.isLetter || $0.isNumber }.count >= 6
            && password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section {
                        Label("Password changed. Sign in with your new password.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.ok)
                    }
                } else {
                    Section {
                        TextField("Phone or email you sign in with", text: $emailOrPhone)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Reset code, e.g. ABCD2345", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    } footer: {
                        Text("Your landlord sends the code by WhatsApp, SMS or Telegram. It works once and expires after 24 hours.")
                    }

                    Section {
                        SecureField("New password", text: $password)
                            .textContentType(.newPassword)
                        SecureField("Type it again", text: $confirmPassword)
                            .textContentType(.newPassword)
                    } footer: {
                        if !password.isEmpty && password.count < 8 {
                            Text("Use at least 8 characters.").foregroundStyle(Theme.danger)
                        } else if !confirmPassword.isEmpty && confirmPassword != password {
                            Text("The two passwords don't match.").foregroundStyle(Theme.danger)
                        }
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                    }
                }
            }
            .disabled(isWorking)
            .navigationTitle("Reset with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if done {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking { ProgressView() } else {
                            Button("Save") { Task { await save() } }.disabled(!canSave)
                        }
                    }
                }
            }
            .onAppear { if emailOrPhone.isEmpty { emailOrPhone = prefill } }
        }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await app.unauthenticatedAPI.resetWithCode(ResetWithCodeRequest(
                emailOrPhone: emailOrPhone.trimmingCharacters(in: .whitespaces),
                code: code,
                newPassword: password))
            done = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
