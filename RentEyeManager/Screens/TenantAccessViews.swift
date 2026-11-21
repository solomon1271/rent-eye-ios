import SwiftUI

/// On a lease (landlord side): who can open it in the tenant app/website, and inviting the tenant.
struct LeaseTenantAccessSection: View {
    @Environment(AppState.self) private var app
    let lease: Lease

    @State private var entries: [LeaseAccessEntry] = []
    @State private var loaded = false
    @State private var showInvite = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if loaded && entries.isEmpty {
                Text("No one can see this lease in Rent Eye yet.")
                    .foregroundStyle(Theme.muted)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.fullName).foregroundStyle(Theme.ink)
                    Text(entry.email).font(.caption).foregroundStyle(Theme.muted)
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
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var accountExists = false
    @State private var granted: LeaseAccessEntry?
    @State private var invite: InviteToShare?

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@")
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
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
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
            } footer: {
                Text("The tenant signs in with this email. You'll get a message with a website link and an app code to send them by WhatsApp, Telegram or SMS. Inviting the same tenant again replaces the old invitation.")
            }

            if let granted {
                Section {
                    Label("\(granted.fullName) can now see this lease. They'll find it under \"Switch lease\" the next time they open Rent Eye.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.ok)
                }
            } else if accountExists {
                Section {
                    Text("\(email) already has a Rent Eye account, for example from another lease. Give that account access to this lease instead of inviting again.")
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
                unit: lease.unit))
            invite = InviteToShare(
                organizationName: result.workspaceName,
                personName: name.trimmingCharacters(in: .whitespaces),
                email: result.email,
                code: result.inviteToken,
                expiresAtUtc: result.expiresAtUtc,
                kind: .tenant,
                webLink: InviteToShare.usableWebLink(result.previewInviteUrl))
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
            granted = try await app.api.grantLeaseAccess(leaseId: lease.id, email: email.trimmingCharacters(in: .whitespaces))
            accountExists = false
        } catch {
            errorMessage = app.handle(error)
        }
    }
}
