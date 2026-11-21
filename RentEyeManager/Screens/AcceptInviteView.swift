import SwiftUI

/// "I have an invitation": a new organisation owner or staff member sets their password, then is signed in.
struct AcceptInviteView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var codeText = ""
    @State private var invite: InviteDetails?
    @State private var fullName = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var passwordProblem: String? {
        if password.isEmpty { return nil }
        if password.count < 8 { return "Use at least 8 characters." }
        if !confirmPassword.isEmpty && confirmPassword != password { return "The two passwords don't match." }
        return nil
    }

    private var canFinish: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 8 && password == confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                if let invite {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(invite.organizationName)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            Text("You're joining as \(invite.kind.roleDescription).")
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Your details") {
                        LabeledContent("Email", value: invite.email)
                        TextField("Full name", text: $fullName)
                            .textContentType(.name)
                        TextField("Phone", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                    }

                    Section {
                        SecureField("New password", text: $password)
                            .textContentType(.newPassword)
                        SecureField("Type it again", text: $confirmPassword)
                            .textContentType(.newPassword)
                    } header: {
                        Text("Choose a password")
                    } footer: {
                        if let passwordProblem {
                            Text(passwordProblem).foregroundStyle(Theme.danger)
                        } else {
                            Text("At least 8 characters. You'll use it with \(invite.email) to sign in.")
                        }
                    }
                } else {
                    Section {
                        TextField("Paste the code or the whole message", text: $codeText, axis: .vertical)
                            .lineLimit(1...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            if let pasted = UIPasteboard.general.string { codeText = pasted }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                    } header: {
                        Text("Invitation code")
                    } footer: {
                        Text("You get the code from whoever invited you, usually by WhatsApp or Telegram.")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isWorking)
            .navigationTitle(invite == nil ? "I have an invitation" : "Set up your account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else if invite == nil {
                        Button("Next") { Task { await lookUp() } }
                            .disabled(InviteCode.extract(from: codeText).count < 16)
                    } else {
                        Button("Finish") { Task { await finish() } }
                            .disabled(!canFinish)
                    }
                }
            }
        }
    }

    private func lookUp() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let details = try await app.unauthenticatedAPI.lookUpInvite(code: InviteCode.extract(from: codeText))
            fullName = details.fullName
            phone = details.phone
            invite = details
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() async {
        guard let invite else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            _ = try await app.unauthenticatedAPI.acceptInvite(invite.kind, AcceptInviteRequest(
                inviteToken: invite.code,
                fullName: fullName.trimmingCharacters(in: .whitespaces),
                email: invite.email,
                phone: phone.trimmingCharacters(in: .whitespaces),
                password: password))
            // The account is ready; sign straight in with the new password.
            let challenge = try await app.signIn(email: invite.email, password: password)
            if challenge != nil {
                errorMessage = "Your account is ready. Sign in with \(invite.email) and your new password."
                return
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
