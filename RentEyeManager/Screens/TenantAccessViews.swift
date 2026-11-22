import SwiftUI

/// On a lease (landlord side): who can open it in the tenant app/website, and inviting the tenant.
struct LeaseTenantAccessSection: View {
    @Environment(AppState.self) private var app
    let lease: Lease

    @State private var entries: [LeaseAccessEntry] = []
    @State private var loaded = false
    @State private var showInvite = false
    @State private var errorMessage: String?
    @State private var resetCode: TenantResetCode?
    @State private var resettingId: String?

    var body: some View {
        Section {
            if loaded && entries.isEmpty {
                Text("No one can see this lease in Rent Eye yet.")
                    .foregroundStyle(Theme.muted)
            }
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.fullName).foregroundStyle(Theme.ink)
                        Text(entry.email).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if app.session?.isAdministrator == true {
                        if resettingId == entry.userId {
                            ProgressView()
                        } else {
                            Menu {
                                Button {
                                    Task { await issueReset(for: entry) }
                                } label: {
                                    Label("Send a password reset code", systemImage: "key")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
            if lease.status != "Ended" {
                Button { showInvite = true } label: {
                    Label("Invite tenant to Rent Eye", systemImage: "person.badge.plus")
                }
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(Theme.danger) }
        } header: {
            Text("Tenant app access")
        } footer: {
            Text("The tenant sees their bills, tells you when they've paid and reports repairs, on the iPhone app or the website.")
        }
        .task { await load() }
        .sheet(isPresented: $showInvite, onDismiss: { Task { await load() } }) {
            InviteTenantSheet(lease: lease)
        }
        .sheet(item: $resetCode) { code in ResetCodeShareSheet(code: code) }
    }

    private func issueReset(for entry: LeaseAccessEntry) async {
        resettingId = entry.userId
        defer { resettingId = nil }
        do {
            resetCode = try await app.api.issueResetCode(leaseId: lease.id, userId: entry.userId)
            errorMessage = nil
        } catch {
            errorMessage = app.handle(error)
        }
    }

    private func load() async {
        do {
            entries = try await app.api.leaseAccess(leaseId: lease.id)
            errorMessage = nil
        } catch {
            errorMessage = app.handle(error)
        }
        loaded = true
    }
}

/// Landlord invites the tenant on a lease: creates the invitation and shows the message to share.
/// If the tenant already has an account (e.g. a second lease), an administrator can give that account
/// access to this lease instead.
struct InviteTenantSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let lease: Lease

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var channel: ContactChannel = .whatsapp
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var accountExists = false
    @State private var granted: LeaseAccessEntry?
    @State private var invite: InviteToShare?

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && isRealPhone(phone)
            && (channel != .email || email.contains("@"))
            && (email.trimmingCharacters(in: .whitespaces).isEmpty || email.contains("@"))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let invite {
                    InviteShareContent(invite: invite)
                } else {
                    form
                }
            }
            .navigationTitle(invite == nil ? "Invite tenant" : "Invitation ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if invite == nil && granted == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking { ProgressView() } else {
                            Button("Create") { Task { await createInvite() } }.disabled(!canSend)
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .onAppear { if name.isEmpty { name = lease.tenant } }
        }
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Lease", value: "\(lease.propertyName) · \(lease.unit)")
                TextField("Tenant's full name", text: $name)
                TextField("Phone, e.g. 0911 22 33 44", text: $phone)
                    .keyboardType(.phonePad)
                TextField(channel == .email ? "Email" : "Email (optional)", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Without an email the tenant signs in with their phone number.")
            }

            Section {
                Picker("Send it by", selection: $channel) {
                    ForEach(ContactChannel.allCases) { option in
                        Label(option.label, systemImage: option.systemImage).tag(option)
                    }
                }
            } footer: {
                Text(channel == .email
                     ? "The invitation is emailed when email is set up on the server; until then your Mail app opens with it ready."
                     : "Your \(channel.label) opens with the message ready; you just press send. It's saved as the tenant's preferred way to be contacted. Inviting the same tenant again replaces the old invitation.")
            }

            if let granted {
                Section {
                    Label("\(granted.fullName) can now see this lease. They'll find it under \"Switch lease\" the next time they open Rent Eye.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.ok)
                }
            } else if accountExists {
                Section {
                    Text("\(accountKey) already has a Rent Eye account, for example from another lease. Give that account access to this lease instead of inviting again.")
                        .foregroundStyle(Theme.ink)
                    if app.session?.isAdministrator == true {
                        Button {
                            Task { await grantAccess() }
                        } label: {
                            Label("Give access to this lease", systemImage: "key")
                        }
                    } else {
                        Text("Only an administrator can do this. Ask your organisation's administrator.")
                            .font(.callout)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Theme.danger) }
            }
        }
        .disabled(isWorking)
    }

    /// The existing account is found by email, or by phone when no email was given.
    private var accountKey: String {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        return trimmedEmail.isEmpty ? phone.trimmingCharacters(in: .whitespaces) : trimmedEmail
    }

    private func createInvite() async {
        isWorking = true
        errorMessage = nil
        accountExists = false
        defer { isWorking = false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        do {
            let result = try await app.api.createTenantInvite(CreateTenantInviteRequest(
                fullName: name.trimmingCharacters(in: .whitespaces),
                email: trimmedEmail,
                phone: phone.trimmingCharacters(in: .whitespaces),
                leaseId: lease.id,
                propertyId: lease.propertyId,
                unit: lease.unit,
                contactChannel: channel.rawValue))
            invite = InviteToShare(
                organizationName: result.workspaceName,
                personName: name.trimmingCharacters(in: .whitespaces),
                email: result.email,
                code: result.inviteToken,
                expiresAtUtc: result.expiresAtUtc,
                kind: .tenant,
                webLink: InviteToShare.usableWebLink(result.previewInviteUrl),
                channel: channel,
                phone: result.phone ?? phone.trimmingCharacters(in: .whitespaces))
        } catch let error as APIError where error.message.localizedCaseInsensitiveContains("already exists") {
            accountExists = true
        } catch {
            errorMessage = app.handle(error)
        }
    }

    private func grantAccess() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            granted = try await app.api.grantLeaseAccess(leaseId: lease.id, email: accountKey)
            accountExists = false
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

/// Shows a tenant's one-time reset code and opens their preferred app to send it.
struct ResetCodeShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let code: TenantResetCode
    @State private var channel: ContactChannel = .whatsapp
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reset code for \(code.fullName)").foregroundStyle(Theme.muted)
                        Text(code.code)
                            .font(.largeTitle.monospaced().weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                        Text("Works once and expires in 24 hours. Their current password stops working once they use it.")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                }

                Section("Send it by") {
                    Picker("Send it by", selection: $channel) {
                        ForEach(ContactChannel.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let url = channel.link(phone: code.phone, email: code.email, message: code.shareText,
                                              webLink: nil, subject: "Your Rent Eye reset code") {
                        Link(destination: url) {
                            Label(channel.actionLabel, systemImage: channel.systemImage)
                        }
                    }
                    ShareLink(item: code.shareText) {
                        Label("Send another way", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = code.shareText
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy message", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
            .navigationTitle("Password reset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { channel = code.channel }
        }
    }
}
