import SwiftUI

/// What a tenant sees after signing in.
struct TenantTabView: View {
    @Environment(TenantStore.self) private var store

    var body: some View {
        TabView {
            TenantHomeView()
                .tabItem { Label("Home", systemImage: "house") }
            TenantBillsView()
                .tabItem { Label("Bills", systemImage: "list.bullet.rectangle") }
                .badge(store.openInvoices.count)
            TenantPaymentsView()
                .tabItem { Label("Payments", systemImage: "banknote") }
            TenantRepairsView()
                .tabItem { Label("Repairs", systemImage: "wrench.and.screwdriver") }
            TenantAccountView()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
    }
}

// MARK: - Home

struct TenantHomeView: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @State private var payInvoice: Invoice?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if store.hasNoLease {
                        noLeaseCard
                    } else if let errorMessage = store.errorMessage {
                        Text(errorMessage).foregroundStyle(Theme.danger)
                    } else if store.lease != nil {
                        balanceCard
                        if !store.pendingPayments.isEmpty { pendingCard }
                        nextBillCard
                        leaseCard
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .overlay { if store.isLoading && !store.hasNoLease && store.lease == nil { ProgressView() } }
            .navigationTitle("Rent Eye")
            .toolbar {
                if store.leases.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) { LeaseSwitcher() }
                }
            }
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
            .sheet(item: $payInvoice) { invoice in TenantPaySheet(invoice: invoice) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TibebBand(height: 6).clipShape(Capsule()).frame(width: 80)
            Text("Hello, \(firstName)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)
            if let lease = store.lease {
                Text("\(lease.propertyName) · Unit \(lease.unit)")
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var firstName: String {
        (store.profile?.name ?? app.session?.fullName ?? "")
            .split(separator: " ").first.map(String.init) ?? "there"
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.balanceDue > 0 ? "You owe" : "All paid")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(Money.etb(store.balanceDue))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if !store.overdueInvoices.isEmpty {
                Text("\(store.overdueInvoices.count) bill\(store.overdueInvoices.count == 1 ? " is" : "s are") overdue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xFFD2CC))
            } else if store.balanceDue == 0 {
                Text("Nothing to pay right now.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.brandDeep, in: RoundedRectangle(cornerRadius: 16))
    }

    private var pendingCard: some View {
        let total = store.pendingPayments.reduce(0) { $0 + $1.amount }
        return Label {
            Text("\(Money.etb(total)) sent and waiting for your landlord to confirm.")
                .foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: "clock").foregroundStyle(Theme.warn)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var nextBillCard: some View {
        if let invoice = store.nextInvoice {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Next bill").font(.headline).foregroundStyle(Theme.ink)
                    Spacer()
                    StatusPill.invoice(invoice.status)
                }
                Text(invoice.billingPeriodLabel).foregroundStyle(Theme.muted)
                HStack {
                    Text(Money.etb(invoice.balanceDue)).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Due").foregroundStyle(Theme.muted)
                        DateLabel(iso: invoice.dueDate).foregroundStyle(Theme.ink)
                    }
                    .font(.subheadline)
                }
                Button {
                    payInvoice = invoice
                } label: {
                    Text("I've paid this")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12))
                }
                Text("Pay by telebirr or bank transfer first, then tap here and enter the transaction reference.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var leaseCard: some View {
        if let lease = store.lease {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your lease").font(.headline).foregroundStyle(Theme.ink)
                LabeledContent("Rent", value: Money.etb(lease.rent))
                LabeledContent("Billing", value: lease.scheduleDescription)
                LabeledContent("Ends") { DateLabel(iso: lease.leaseEnd) }
                LabeledContent("Managed by", value: lease.manager)
            }
            .font(.subheadline)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var noLeaseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Your account isn't linked to a lease yet", systemImage: "link.badge.plus")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Ask your landlord to give \(app.session?.email ?? "your email") access to your lease. Then pull down here to refresh.")
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Lets a tenant with several leases (e.g. a flat and a shop) choose which one to look at.
struct LeaseSwitcher: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store

    var body: some View {
        Menu {
            ForEach(store.leases) { lease in
                Button {
                    Task { await store.select(leaseId: lease.id, using: app) }
                } label: {
                    if lease.id == store.lease?.id {
                        Label("\(lease.propertyName) · \(lease.unit)", systemImage: "checkmark")
                    } else {
                        Text("\(lease.propertyName) · \(lease.unit)")
                    }
                }
            }
        } label: {
            Label("Switch lease", systemImage: "arrow.left.arrow.right")
        }
    }
}

// MARK: - Bills

struct TenantBillsView: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @State private var showPaid = false

    private var shown: [Invoice] {
        let sorted = store.invoices.sorted { $0.dueDate > $1.dueDate }
        return showPaid ? sorted : sorted.filter(\.isOpen)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show paid bills", isOn: $showPaid)
                }
                Section {
                    if shown.isEmpty && store.loadedOnceOrNoLease {
                        Text(showPaid ? "No bills yet." : "No unpaid bills. You're up to date.")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(shown) { invoice in
                        NavigationLink(value: invoice) { TenantInvoiceRow(invoice: invoice) }
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Bills")
            .navigationDestination(for: Invoice.self) { invoice in TenantInvoiceDetailView(invoice: invoice) }
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
        }
    }
}

private struct TenantInvoiceRow: View {
    let invoice: Invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(invoice.billingPeriodLabel).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                StatusPill.invoice(invoice.status)
            }
            HStack {
                Text(Money.etb(invoice.isOpen ? invoice.balanceDue : invoice.amount)).foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 4) {
                    Text("Due").foregroundStyle(Theme.muted)
                    DateLabel(iso: invoice.dueDate).foregroundStyle(Theme.muted)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TenantInvoiceDetailView: View {
    @Environment(TenantStore.self) private var store
    let invoice: Invoice
    @State private var showPay = false

    private var current: Invoice { store.invoices.first { $0.id == invoice.id } ?? invoice }
    private var relatedPayments: [Payment] { store.payments.filter { $0.invoiceId == invoice.id } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    StatusPill.invoice(current.status)
                    Text(current.billingPeriodLabel).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("\(current.propertyName) · Unit \(current.unit)").foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
            }

            Section("Amount") {
                ForEach(Array(current.lines.enumerated()), id: \.offset) { item in
                    LabeledContent(item.element.label, value: Money.etb(item.element.amount))
                }
                LabeledContent("Total", value: Money.etb(current.amount)).fontWeight(.semibold)
                LabeledContent("Paid", value: Money.etb(current.amountPaid))
                LabeledContent("Still to pay", value: Money.etb(current.balanceDue)).fontWeight(.semibold)
                let pending = store.pendingAmount(for: current)
                if pending > 0 {
                    LabeledContent("Waiting for confirmation", value: Money.etb(pending)).foregroundStyle(Theme.warn)
                }
            }

            Section("Dates") {
                LabeledContent("Issued") { DateLabel(iso: current.issuedDate) }
                LabeledContent("Due") { DateLabel(iso: current.dueDate) }
                LabeledContent("Period") {
                    HStack(spacing: 4) { DateLabel(iso: current.billingPeriodStart); Text("–"); DateLabel(iso: current.billingPeriodEnd) }
                }
            }

            if !relatedPayments.isEmpty {
                Section("Payments for this bill") {
                    ForEach(relatedPayments) { payment in TenantPaymentRow(payment: payment) }
                }
            }

            if current.isOpen {
                Section {
                    Button { showPay = true } label: {
                        Label("I've paid this", systemImage: "checkmark.circle")
                            .font(.headline)
                    }
                } footer: {
                    Text("Pay by telebirr or bank transfer first, then enter the transaction reference so your landlord can confirm it.")
                }
            }
        }
        .screenBackground()
        .navigationTitle("Bill")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPay) { TenantPaySheet(invoice: current) }
    }
}

// MARK: - "I've paid" (payment submission)

struct TenantPaySheet: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let invoice: Invoice

    @State private var provider = TenantOptions.providers[0]
    @State private var amountText = ""
    @State private var paidOn = Date()
    @State private var reference = ""
    @State private var note = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var sent: Payment?

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    private var canSend: Bool {
        (amount ?? 0) > 0 && reference.trimmingCharacters(in: .whitespaces).count >= 4
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sent {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Sent to your landlord", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .foregroundStyle(Theme.ok)
                            Text("\(Money.etb(sent.amount)) by \(sent.method), reference \(sent.reference). It shows as waiting until your landlord checks it; the bill updates when they confirm.")
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        LabeledContent("Bill", value: invoice.billingPeriodLabel)
                        LabeledContent("Still to pay", value: Money.etb(invoice.balanceDue))
                    }

                    Section {
                        Picker("Paid with", selection: $provider) {
                            ForEach(TenantOptions.providers, id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Amount paid (ETB)", text: $amountText)
                            .keyboardType(.decimalPad)
                        DatePicker("Paid on", selection: $paidOn, in: ...Date(), displayedComponents: .date)
                        TextField("Transaction reference, \(TenantOptions.referenceHint(for: provider))", text: $reference)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        TextField("Note for your landlord (optional)", text: $note, axis: .vertical)
                    } header: {
                        Text("Payment details")
                    } footer: {
                        Text("The reference is on your telebirr or bank receipt (SMS). Your landlord uses it to find your payment.")
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                    }
                }
            }
            .disabled(isWorking)
            .navigationTitle(sent == nil ? "I've paid" : "Thank you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sent == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if isWorking { ProgressView() } else {
                            Button("Send") { Task { await send() } }.disabled(!canSend)
                        }
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .onAppear {
                if amountText.isEmpty {
                    let remaining = max(invoice.balanceDue - store.pendingAmount(for: invoice), 0)
                    amountText = remaining > 0 ? Self.plain(remaining) : ""
                }
            }
        }
    }

    private static func plain(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func send() async {
        guard let amount else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            let payment = try await app.api.submitTenantPayment(TenantPaymentSubmission(
                invoiceId: invoice.id,
                provider: provider,
                amount: amount,
                paymentDate: AppDate.iso(from: paidOn),
                reference: reference.trimmingCharacters(in: .whitespaces),
                note: trimmedNote.isEmpty ? nil : trimmedNote))
            sent = payment
            await store.load(using: app)
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

// MARK: - Payments

struct TenantPaymentsView: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                if store.payments.isEmpty && store.loadedOnceOrNoLease {
                    Text("No payments yet. When you pay a bill, tap \"I've paid this\" on it.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(store.payments) { payment in TenantPaymentRow(payment: payment) }
            }
            .screenBackground()
            .navigationTitle("Payments")
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
        }
    }
}

struct TenantPaymentRow: View {
    let payment: Payment

    private var statusText: String {
        switch payment.status ?? "Approved" {
        case "Pending": return "Waiting for landlord"
        case "Rejected": return "Not accepted"
        default: return "Confirmed"
        }
    }

    private var tone: StatusPill.Tone {
        switch payment.status ?? "Approved" {
        case "Pending": return .warning
        case "Rejected": return .danger
        default: return .good
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Money.etb(payment.amount)).font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                StatusPill(text: statusText, tone: tone)
            }
            HStack(spacing: 4) {
                Text("\(payment.method) · \(payment.reference) ·").foregroundStyle(Theme.muted)
                DateLabel(iso: payment.paymentDate).foregroundStyle(Theme.muted)
            }
            .font(.caption)
            if payment.status == "Rejected", let reason = payment.reviewNote, !reason.isEmpty {
                Text("Reason: \(reason)").font(.caption).foregroundStyle(Theme.danger)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Repairs

struct TenantRepairsView: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                if store.tickets.isEmpty && store.loadedOnceOrNoLease {
                    Text("No repair requests. Tap + to report something that needs fixing.")
                        .foregroundStyle(Theme.muted)
                }
                ForEach(store.tickets) { ticket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ticket.issue).font(.headline).foregroundStyle(Theme.ink)
                            Spacer()
                            StatusPill(text: ticket.status, tone: ticket.statusTone)
                        }
                        Text([ticket.category, ticket.priority].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        if let next = ticket.nextAction, !next.isEmpty, !ticket.isClosed {
                            Text(next).font(.caption).foregroundStyle(Theme.ink)
                        }
                        if let note = ticket.resolutionNote, !note.isEmpty, ticket.isClosed {
                            Text(note).font(.caption).foregroundStyle(Theme.ok)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .screenBackground()
            .navigationTitle("Repairs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Report a repair")
                        .disabled(store.lease == nil)
                }
            }
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
            .sheet(isPresented: $showNew) { NewRepairSheet() }
        }
    }
}

struct NewRepairSheet: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var issue = ""
    @State private var category = TenantOptions.categories[0]
    @State private var priority = TenantOptions.priorities[0]
    @State private var accessWindow = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs fixing? e.g. Kitchen tap is leaking", text: $issue, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Type", selection: $category) {
                        ForEach(TenantOptions.categories, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("How urgent", selection: $priority) {
                        ForEach(TenantOptions.priorities, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("When can someone come in? (optional)", text: $accessWindow)
                } footer: {
                    Text("Urgent means it can't wait, like no water, a flood or no power.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isWorking)
            .navigationTitle("Report a repair")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking { ProgressView() } else {
                        Button("Send") { Task { await send() } }
                            .disabled(issue.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                    }
                }
            }
        }
    }

    private func send() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        let window = accessWindow.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await app.api.createMaintenanceRequest(CreateMaintenanceRequest(
                issue: issue.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                priority: priority,
                accessWindow: window.isEmpty ? nil : window), leaseId: store.selectedLeaseId)
            await store.load(using: app)
            dismiss()
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

// MARK: - Account

struct TenantAccountView: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @AppStorage("calendar") private var calendar = CalendarSystem.gregorian.rawValue
    @State private var showEdit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    LabeledContent("Name", value: store.profile?.name ?? app.session?.fullName ?? "")
                    LabeledContent("Email", value: app.session?.email ?? "")
                    LabeledContent("Phone", value: store.profile?.phone ?? "—")
                    Button("Edit my details") { showEdit = true }
                        .disabled(store.lease == nil)
                }

                if let lease = store.lease {
                    Section("Landlord") {
                        LabeledContent("Organisation", value: app.session?.workspaceName ?? "")
                        LabeledContent("Building", value: lease.propertyName)
                        LabeledContent("Unit", value: lease.unit)
                    }
                }

                Section("Dates") {
                    Picker("Calendar", selection: $calendar) {
                        ForEach(CalendarSystem.allCases) { system in
                            Text(system == .gregorian ? "Gregorian (G.C.)" : "Ethiopian (E.C.)").tag(system.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showEdit) { TenantProfileEditor() }
        }
    }
}

struct TenantProfileEditor: View {
    @Environment(AppState.self) private var app
    @Environment(TenantStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var occupation = ""
    @State private var employer = ""
    @State private var emergencyName = ""
    @State private var emergencyPhone = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Full name", text: $name)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                    TextField("Current address", text: $address)
                }
                Section("Work") {
                    TextField("Occupation", text: $occupation)
                    TextField("Employer", text: $employer)
                }
                Section("Emergency contact") {
                    TextField("Name", text: $emergencyName)
                    TextField("Phone", text: $emergencyPhone).keyboardType(.phonePad)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isWorking)
            .navigationTitle("My details")
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
            .onAppear(perform: fill)
        }
    }

    /// "Not provided" is the server's placeholder; show an empty box instead.
    private static func editable(_ value: String?) -> String {
        guard let value, value != "Not provided" else { return "" }
        return value
    }

    private func fill() {
        let profile = store.profile
        name = Self.editable(profile?.name ?? app.session?.fullName)
        phone = Self.editable(profile?.phone)
        address = Self.editable(profile?.currentAddress)
        occupation = Self.editable(profile?.occupation)
        employer = Self.editable(profile?.employer)
        emergencyName = Self.editable(profile?.emergencyContactName)
        emergencyPhone = Self.editable(profile?.emergencyContactPhone)
    }

    private func save() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespaces) }
        do {
            store.profile = try await app.api.updateTenantProfile(UpdateTenantProfileRequest(
                name: clean(name),
                phone: clean(phone),
                email: app.session?.email ?? "",
                currentAddress: clean(address),
                occupation: clean(occupation),
                employer: clean(employer),
                emergencyContactName: clean(emergencyName),
                emergencyContactPhone: clean(emergencyPhone)), leaseId: store.selectedLeaseId)
            dismiss()
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

extension TenantStore {
    /// Empty-state text only after the first load finished (or there's no lease), so it doesn't flash.
    var loadedOnceOrNoLease: Bool { !isLoading || hasNoLease }
}
