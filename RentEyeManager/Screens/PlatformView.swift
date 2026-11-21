import SwiftUI

/// What the platform admin sees after signing in: every organisation on Rent Eye.
struct PlatformHomeView: View {
    @Environment(AppState.self) private var app
    @State private var organizations: [PlatformOrganization] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorMessage: String?
    @State private var search = ""
    @State private var showNew = false
    @State private var showSettings = false
    @State private var inviteToShare: InviteToShare?

    private var filtered: [PlatformOrganization] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let sorted = organizations.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.administratorName ?? "").localizedCaseInsensitiveContains(query)
                || ($0.administratorEmail ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                    }
                }

                Section("Organisations") {
                    if filtered.isEmpty && loadedOnce {
                        Text(search.isEmpty ? "No organisations yet. Tap + to add the first one." : "No organisation matches \"\(search)\".")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(filtered) { organization in
                        NavigationLink(value: organization) {
                            OrganizationRow(organization: organization)
                        }
                    }
                }
            }
            .screenBackground()
            .overlay { if isLoading && !loadedOnce { ProgressView("Loading organisations…") } }
            .searchable(text: $search, prompt: "Search organisations or owners")
            .navigationTitle("Rent Eye platform")
            .navigationDestination(for: PlatformOrganization.self) { organization in
                OrganizationDetailView(organization: organization) { await load() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New organisation")
                }
            }
            .refreshable { await load() }
            .task { if !loadedOnce { await load() } }
            .sheet(isPresented: $showNew) {
                NewOrganizationSheet { invite in
                    inviteToShare = invite
                    Task { await load() }
                }
            }
            .sheet(item: $inviteToShare) { invite in
                InviteShareSheet(invite: invite)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        let active = organizations.filter { $0.accountStatus == "active" }.count
        let waiting = organizations.filter(\.isWaitingForOwner).count
        let properties = organizations.reduce(0) { $0 + $1.propertyCount }
        return VStack(alignment: .leading, spacing: 12) {
            TibebBand(height: 6).clipShape(Capsule()).frame(width: 80)
            Text("Signed in as \(app.session?.fullName ?? "platform admin")")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricCard(label: "Organisations", value: "\(organizations.count)", highlight: true)
                MetricCard(label: "Active", value: "\(active)")
                MetricCard(label: "Waiting for owner", value: "\(waiting)")
                MetricCard(label: "Properties", value: "\(properties)")
            }
        }
        .padding(.vertical, 8)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            organizations = try await app.api.organizations()
            errorMessage = nil
            loadedOnce = true
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

private struct OrganizationRow: View {
    let organization: PlatformOrganization

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(organization.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                StatusPill(text: organization.statusLabel, tone: organization.statusTone)
            }
            Text(organization.administratorName ?? organization.administratorEmail ?? "No owner yet")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Text("\(organization.propertyCount) properties · \(organization.activeUserCount) people · \(PlatformOptions.label(organization.subscriptionPlan)) (\(PlatformOptions.label(organization.subscriptionStatus)))")
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Organisation detail

struct OrganizationDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var organization: PlatformOrganization
    let onChange: () async -> Void

    @State private var showEdit = false
    @State private var inviteToShare: InviteToShare?
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var deleteConfirmation = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    StatusPill(text: organization.statusLabel, tone: organization.statusTone)
                    Text(organization.name).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("/\(organization.slug)").font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle").foregroundStyle(Theme.ok) }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Theme.danger) }
            }

            Section("Owner (administrator)") {
                LabeledContent("Name", value: organization.administratorName ?? "—")
                LabeledContent("Email", value: organization.administratorEmail ?? "—")
                LabeledContent("Account set up", value: organization.isWaitingForOwner ? "Not yet" : "Yes")
                if organization.hasPendingInvite, let expires = organization.pendingInviteExpiresAtUtc {
                    LabeledContent("Invitation expires") { DateLabel(iso: expires) }
                }
            }

            Section("Subscription") {
                LabeledContent("Plan", value: PlatformOptions.label(organization.subscriptionPlan))
                LabeledContent("Status", value: PlatformOptions.label(organization.subscriptionStatus))
                if let renews = organization.subscriptionRenewsAtUtc {
                    LabeledContent("Renews") { DateLabel(iso: renews) }
                }
            }

            Section("Usage") {
                LabeledContent("Properties", value: "\(organization.propertyCount)")
                LabeledContent("People with access", value: "\(organization.activeUserCount)")
                LabeledContent("Created") { DateLabel(iso: organization.createdAtUtc) }
            }

            Section {
                Button {
                    Task { await resendInvite() }
                } label: {
                    Label(organization.isWaitingForOwner ? "Send the invitation again" : "Send a new owner invitation",
                          systemImage: "paperplane")
                }
                Button { showEdit = true } label: { Label("Edit organisation", systemImage: "pencil") }
            } footer: {
                Text("There's no email on the server yet, so you get an invitation code to share by WhatsApp or Telegram.")
            }

            Section {
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Reset owner access", systemImage: "arrow.counterclockwise")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete organisation", systemImage: "trash")
                }
            } header: {
                Text("Careful")
            } footer: {
                Text("Reset removes the administrator accounts (staff and tenants stay) and creates a new invitation. Delete removes the organisation and all its data for good.")
            }
        }
        .screenBackground()
        .disabled(isWorking)
        .overlay { if isWorking { ProgressView() } }
        .navigationTitle(organization.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            EditOrganizationSheet(organization: organization) { result in
                organization = result.organization
                message = result.message
                Task { await onChange() }
            }
        }
        .sheet(item: $inviteToShare) { invite in InviteShareSheet(invite: invite) }
        .confirmationDialog("Reset owner access for \(organization.name)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset owner access", role: .destructive) { Task { await resetAccounts() } }
        } message: {
            Text("The current administrator accounts are removed and a new invitation is created. Staff, tenants and data stay.")
        }
        .alert("Delete \(organization.name)?", isPresented: $confirmDelete) {
            TextField("Type the organisation name", text: $deleteConfirmation)
            Button("Delete for good", role: .destructive) { Task { await deleteOrganization() } }
                .disabled(deleteConfirmation.trimmingCharacters(in: .whitespaces) != organization.name)
            Button("Cancel", role: .cancel) { deleteConfirmation = "" }
        } message: {
            Text("This removes its properties, leases, invoices, payments and accounts. It can't be undone. Type \"\(organization.name)\" to confirm.")
        }
    }

    private func resendInvite() async {
        await run {
            let result = try await app.api.resendInvite(organizationId: organization.id)
            message = "New invitation ready to share."
            inviteToShare = InviteToShare(
                organizationName: organization.name,
                personName: organization.administratorName ?? "there",
                email: organization.administratorEmail ?? "",
                code: result.inviteToken,
                expiresAtUtc: result.expiresAtUtc)
        }
    }

    private func resetAccounts() async {
        await run {
            let result = try await app.api.resetAccounts(organizationId: organization.id)
            message = result.message
            await onChange()
            // A reset creates a fresh invitation; fetch it so it can be shared straight away.
            let resent = try await app.api.resendInvite(organizationId: organization.id)
            inviteToShare = InviteToShare(
                organizationName: organization.name,
                personName: organization.administratorName ?? "there",
                email: organization.administratorEmail ?? "",
                code: resent.inviteToken,
                expiresAtUtc: resent.expiresAtUtc)
        }
    }

    private func deleteOrganization() async {
        guard deleteConfirmation.trimmingCharacters(in: .whitespaces) == organization.name else { return }
        await run {
            _ = try await app.api.deleteOrganization(id: organization.id)
            await onChange()
            dismiss()
        }
        deleteConfirmation = ""
    }

    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do { try await action() } catch { errorMessage = app.handle(error) }
    }
}

// MARK: - New organisation

struct NewOrganizationSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let onCreated: (InviteToShare) -> Void

    @State private var name = ""
    @State private var slug = ""
    @State private var slugEdited = false
    @State private var ownerName = ""
    @State private var ownerEmail = ""
    @State private var ownerPhone = ""
    @State private var plan = "standard"
    @State private var subscriptionStatus = "trial"
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && slug.count >= 3
            && !ownerName.trimmingCharacters(in: .whitespaces).isEmpty
            && ownerEmail.contains("@")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Organisation") {
                    TextField("Name, e.g. Abebe Properties", text: $name)
                        .onChange(of: name) { _, newValue in
                            if !slugEdited { slug = PlatformOptions.slug(from: newValue) }
                        }
                    TextField("Short name (web address)", text: Binding(
                        get: { slug },
                        set: { slug = PlatformOptions.slug(from: $0); slugEdited = true }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Full name", text: $ownerName)
                        .textContentType(.name)
                    TextField("Email", text: $ownerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone (optional)", text: $ownerPhone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("Owner")
                } footer: {
                    Text("The owner becomes the organisation's administrator. They set their own password from the invitation.")
                }

                Section("Subscription") {
                    Picker("Plan", selection: $plan) {
                        ForEach(PlatformOptions.plans, id: \.self) { Text(PlatformOptions.label($0)).tag($0) }
                    }
                    Picker("Status", selection: $subscriptionStatus) {
                        ForEach(PlatformOptions.subscriptionStatuses, id: \.self) { Text(PlatformOptions.label($0)).tag($0) }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isWorking)
            .navigationTitle("New organisation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking { ProgressView() } else {
                        Button("Create") { Task { await create() } }.disabled(!canSave)
                    }
                }
            }
        }
    }

    private func create() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let request = CreateOrganizationRequest(
            organizationName: name.trimmingCharacters(in: .whitespaces),
            workspaceSlug: slug,
            administratorFullName: ownerName.trimmingCharacters(in: .whitespaces),
            administratorEmail: ownerEmail.trimmingCharacters(in: .whitespaces),
            administratorPhone: ownerPhone.trimmingCharacters(in: .whitespaces),
            subscriptionPlan: plan,
            subscriptionStatus: subscriptionStatus,
            subscriptionRenewsAtUtc: nil)
        do {
            let result = try await app.api.createOrganization(request)
            let invite = InviteToShare(
                organizationName: request.organizationName,
                personName: request.administratorFullName,
                email: result.administratorEmail,
                code: result.inviteToken,
                expiresAtUtc: result.expiresAtUtc)
            dismiss()
            onCreated(invite)
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

// MARK: - Edit organisation

struct EditOrganizationSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let organization: PlatformOrganization
    let onSaved: (UpdateOrganizationResult) -> Void

    @State private var name = ""
    @State private var ownerName = ""
    @State private var ownerEmail = ""
    @State private var accountStatus = "active"
    @State private var plan = "standard"
    @State private var subscriptionStatus = "trial"
    @State private var hasRenewal = false
    @State private var renewsOn = Date()
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var emailChanged: Bool {
        ownerEmail.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(organization.administratorEmail ?? "") != .orderedSame
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Organisation") {
                    TextField("Name", text: $name)
                    Picker("Account", selection: $accountStatus) {
                        ForEach(PlatformOptions.accountStatuses, id: \.self) { Text(PlatformOptions.label($0)).tag($0) }
                    }
                }

                Section {
                    TextField("Owner name", text: $ownerName)
                    TextField("Owner email", text: $ownerEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Owner")
                } footer: {
                    if emailChanged {
                        Text("Changing the email hands the organisation to a new owner. They get an invitation; the current owner keeps access until they accept, then becomes staff.")
                            .foregroundStyle(Theme.warn)
                    }
                }

                Section("Subscription") {
                    Picker("Plan", selection: $plan) {
                        ForEach(PlatformOptions.plans, id: \.self) { Text(PlatformOptions.label($0)).tag($0) }
                    }
                    Picker("Status", selection: $subscriptionStatus) {
                        ForEach(PlatformOptions.subscriptionStatuses, id: \.self) { Text(PlatformOptions.label($0)).tag($0) }
                    }
                    Toggle("Has a renewal date", isOn: $hasRenewal)
                    if hasRenewal {
                        DatePicker("Renews on", selection: $renewsOn, displayedComponents: .date)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isWorking)
            .navigationTitle("Edit organisation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking { ProgressView() } else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear {
                name = organization.name
                ownerName = organization.administratorName ?? ""
                ownerEmail = organization.administratorEmail ?? ""
                accountStatus = organization.accountStatus
                plan = organization.subscriptionPlan
                subscriptionStatus = organization.subscriptionStatus
                if let renews = organization.subscriptionRenewsAtUtc, let date = AppDate.date(from: renews) {
                    hasRenewal = true
                    renewsOn = date
                }
            }
        }
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let request = UpdateOrganizationRequest(
            organizationName: name.trimmingCharacters(in: .whitespaces),
            administratorFullName: ownerName.trimmingCharacters(in: .whitespaces),
            administratorEmail: ownerEmail.trimmingCharacters(in: .whitespaces),
            administratorPhone: nil,
            accountStatus: accountStatus,
            subscriptionStatus: subscriptionStatus,
            subscriptionPlan: plan,
            subscriptionRenewsAtUtc: hasRenewal ? AppDate.iso(from: renewsOn) + "T00:00:00Z" : nil)
        do {
            let result = try await app.api.updateOrganization(id: organization.id, request)
            dismiss()
            onSaved(result)
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

// MARK: - Sharing an invitation

struct InviteShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let invite: InviteToShare

    var body: some View {
        NavigationStack {
            InviteShareContent(invite: invite)
                .navigationTitle(invite.organizationName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// The code (and website link) to send, with Share and Copy buttons.
struct InviteShareContent: View {
    let invite: InviteToShare
    @State private var copied = false

    private var instructions: String {
        let app = "On iPhone they install Rent Eye, tap \"I have an invitation\" and enter the code."
        let web = invite.webLink == nil ? "" : " On Android or a computer they open the link instead."
        return "Send this to \(invite.personName). \(app)\(web) It only works with \(invite.email)."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Invitation ready", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ok)

                Text(instructions)
                    .foregroundStyle(Theme.ink)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Invitation code").font(.footnote.weight(.semibold)).foregroundStyle(Theme.brand)
                    Text(InviteShareContent.grouped(invite.code))
                        .font(.title3.monospaced().weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    if let link = invite.webLink {
                        Text("Website link").font(.footnote.weight(.semibold)).foregroundStyle(Theme.brand).padding(.top, 6)
                        Text(link)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                    }
                    if let expires = invite.expiresAtUtc {
                        HStack(spacing: 4) {
                            Text("Expires").font(.caption).foregroundStyle(Theme.muted)
                            DateLabel(iso: expires).font(.caption).foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: 14))

                ShareLink(item: invite.shareText) {
                    Label("Share by WhatsApp, Telegram…", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    UIPasteboard.general.string = invite.shareText
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy message", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("There's no email on the server yet, so the invitation isn't sent automatically. Inviting the same person again replaces this code.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(20)
        }
        .background(Theme.background)
    }

    /// "3f2a…" in groups of four so it's easy to read out over the phone.
    static func grouped(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { start in
            let begin = code.index(code.startIndex, offsetBy: start)
            let end = code.index(begin, offsetBy: min(4, code.count - start))
            return String(code[begin..<end])
        }.joined(separator: " ")
    }
}
