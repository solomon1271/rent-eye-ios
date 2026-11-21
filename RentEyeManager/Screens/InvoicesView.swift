import SwiftUI

struct InvoicesView: View {
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @State private var filter = Filter.open
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case open = "Open", overdue = "Overdue", paid = "Paid", all = "All"
        var id: String { rawValue }
    }

    private var filtered: [Invoice] {
        store.invoices
            .filter { invoice in
                switch filter {
                case .open: return invoice.isOpen
                case .overdue: return invoice.status == "Overdue"
                case .paid: return !invoice.isOpen
                case .all: return true
                }
            }
            .filter { search.isEmpty || "\($0.tenant) \($0.propertyName) \($0.unit) \($0.billingPeriodLabel)".localizedCaseInsensitiveContains(search) }
            .sorted { filter == .paid ? $0.dueDate > $1.dueDate : $0.dueDate < $1.dueDate }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if filtered.isEmpty && !store.isLoading {
                    Text(filter == .overdue ? "Nothing overdue." : "No invoices here.").foregroundStyle(Theme.muted)
                }
                ForEach(filtered) { invoice in
                    NavigationLink(value: invoice) { InvoiceRow(invoice: invoice, showTenant: true) }
                }
            }
            .screenBackground()
            .searchable(text: $search, prompt: "Tenant, building or period")
            .navigationTitle("Invoices")
            .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoiceId: $0.id) }
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
        }
    }
}

struct InvoiceRow: View {
    let invoice: Invoice
    let showTenant: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(showTenant ? invoice.tenant : invoice.billingPeriodLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                StatusPill.invoice(invoice.status)
            }
            HStack {
                Text(showTenant ? "\(invoice.billingPeriodLabel) · \(invoice.unit)" : "Due")
                if !showTenant { DateLabel(iso: invoice.dueDate) }
                Spacer()
                Text(invoice.isOpen ? Money.etb(invoice.balanceDue) : Money.etb(invoice.amount))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(invoice.status == "Overdue" ? Theme.danger : Theme.ink)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
    }
}

struct InvoiceDetailView: View {
    let invoiceId: String
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @State private var showRecordPayment = false

    private var invoice: Invoice? { store.invoices.first { $0.id == invoiceId } }
    private var payments: [Payment] { store.payments.filter { $0.invoiceId == invoiceId }.sorted { $0.paymentDate > $1.paymentDate } }

    var body: some View {
        List {
            if let invoice {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invoice.tenant).font(.headline)
                            Text("\(invoice.propertyName) · \(invoice.unit)").font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        StatusPill.invoice(invoice.status)
                    }
                    LabeledContent("Period", value: invoice.billingPeriodLabel)
                    LabeledContent("Due") { DateLabel(iso: invoice.dueDate) }
                    if invoice.status == "Overdue" {
                        LabeledContent("Days late", value: "\(invoice.daysLate)")
                    }
                }

                Section("Amount") {
                    ForEach(Array(invoice.lines.enumerated()), id: \.offset) { item in
                        LabeledContent(item.element.label, value: Money.etb(item.element.amount))
                    }
                    LabeledContent("Total") { Text(Money.etb(invoice.amount)).bold() }
                    if invoice.amountPaid > 0 {
                        LabeledContent("Paid (approved)", value: "−\(Money.etb(invoice.amountPaid))")
                    }
                    LabeledContent("Balance due") {
                        Text(Money.etb(invoice.balanceDue)).bold().foregroundStyle(invoice.isOpen ? Theme.danger : Theme.ok)
                    }
                    if invoice.isOpen {
                        Button {
                            showRecordPayment = true
                        } label: {
                            Label("Record a payment", systemImage: "plus.circle")
                        }
                    }
                }

                Section("Payments") {
                    if payments.isEmpty {
                        Text("No payments yet.").foregroundStyle(Theme.muted)
                    }
                    ForEach(payments) { payment in
                        PaymentRow(payment: payment)
                    }
                }
            } else {
                EmptyStateView(title: "Invoice not found", message: "Pull to refresh on the Invoices tab.")
            }
        }
        .screenBackground()
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRecordPayment) {
            if let invoice { RecordPaymentSheet(invoice: invoice) }
        }
    }
}

/// Staff record a payment they received directly (cash, transfer they've already checked). It counts at once.
struct RecordPaymentSheet: View {
    let invoice: Invoice
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date()
    @State private var method = "CBE Transfer"
    @State private var reference = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let methods = ["CBE Transfer", "telebirr", "Chapa", "Bank Transfer", "Cash", "Check"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount (ETB)", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Paid on", selection: $date, in: ...Date(), displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(methods, id: \.self) { Text($0) }
                    }
                    TextField("Reference", text: $reference)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Balance due: \(Money.etb(invoice.balanceDue)). Anything above it is kept as credit for the tenant.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .onAppear { amount = invoice.balanceDue.rounded() == invoice.balanceDue ? String(Int(invoice.balanceDue)) : String(invoice.balanceDue) }
        }
    }

    private func save() async {
        let value = Double(amount.replacingOccurrences(of: ",", with: "")) ?? 0
        guard value > 0 else {
            errorMessage = "Enter the amount received."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let applied = min(value, invoice.balanceDue)
        let payment = Payment(
            id: "payment-\(UUID().uuidString.lowercased())",
            invoiceId: invoice.id,
            leaseId: invoice.leaseId,
            propertyId: invoice.propertyId,
            propertyName: invoice.propertyName,
            unit: invoice.unit,
            tenant: invoice.tenant,
            manager: invoice.manager,
            amount: value,
            appliedAmount: applied,
            creditRemaining: max(value - applied, 0),
            paymentDate: AppDate.iso(from: date),
            method: method,
            reference: reference.trimmingCharacters(in: .whitespaces).isEmpty ? "Manual payment entry" : reference.trimmingCharacters(in: .whitespaces),
            note: "Recorded in the Rent Eye app."
        )
        do {
            let saved = try await app.api.recordPayment(payment)
            store.replace(saved)
            await store.reloadInvoices(using: app)
            dismiss()
        } catch {
            errorMessage = app.handle(error)
        }
    }
}
