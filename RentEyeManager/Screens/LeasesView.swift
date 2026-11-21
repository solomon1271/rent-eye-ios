import SwiftUI

struct LeasesView: View {
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @State private var search = ""
    @State private var showEnded = false

    private var filtered: [Lease] {
        store.leases
            .filter { showEnded || $0.status != "Ended" }
            .filter { search.isEmpty || "\($0.tenant) \($0.propertyName) \($0.unit)".localizedCaseInsensitiveContains(search) }
            .sorted { ($0.propertyName, $0.unit) < ($1.propertyName, $1.unit) }
    }

    var body: some View {
        NavigationStack {
            List {
                Toggle("Show ended leases", isOn: $showEnded)
                ForEach(filtered) { lease in
                    NavigationLink(value: lease) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(lease.tenant).font(.headline).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(Money.etb(lease.rent)).font(.subheadline.monospacedDigit())
                            }
                            Text("\(lease.propertyName) · \(lease.unit)").font(.caption).foregroundStyle(Theme.muted)
                            HStack(spacing: 4) {
                                Text("Ends")
                                DateLabel(iso: lease.leaseEnd)
                                Text("· \(lease.status)")
                            }
                            .font(.caption)
                            .foregroundStyle(lease.status == "Active" ? Theme.muted : Theme.warn)
                        }
                    }
                }
            }
            .screenBackground()
            .searchable(text: $search, prompt: "Tenant, building or unit")
            .navigationTitle("Leases")
            .navigationDestination(for: Lease.self) { LeaseDetailView(leaseId: $0.id) }
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
        }
    }
}

struct LeaseDetailView: View {
    let leaseId: String
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @State private var isIssuing = false
    @State private var message: String?
    @State private var errorMessage: String?

    private var lease: Lease? { store.leases.first { $0.id == leaseId } }
    private var invoices: [Invoice] { store.invoices.filter { $0.leaseId == leaseId }.sorted { $0.dueDate > $1.dueDate } }

    var body: some View {
        List {
            if let lease {
                Section {
                    LabeledContent("Building", value: lease.propertyName)
                    LabeledContent("Unit", value: lease.unit)
                    LabeledContent("Rent per month", value: Money.etb(lease.rent))
                    LabeledContent("Deposit", value: Money.etb(lease.deposit))
                    LabeledContent("Starts") { DateLabel(iso: lease.leaseStart) }
                    LabeledContent("Ends") { DateLabel(iso: lease.leaseEnd) }
                    LabeledContent("Status", value: lease.status)
                }

                Section {
                    LabeledContent("Schedule", value: lease.scheduleDescription)
                    if let service = lease.serviceCharge, service > 0 {
                        LabeledContent("Service charge", value: "\(Money.etb(service)) / month")
                    }
                    if let tax = lease.taxRate, tax > 0 {
                        LabeledContent("Tax", value: "\(tax.formatted())%")
                    }
                    if lease.status != "Ended" {
                        Button {
                            Task { await issueNext() }
                        } label: {
                            HStack {
                                Label("Issue next invoice", systemImage: "doc.badge.plus")
                                if isIssuing { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(isIssuing)
                    }
                    if let message { Text(message).font(.callout).foregroundStyle(Theme.ok) }
                    if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(Theme.danger) }
                } header: {
                    Text("Billing")
                }

                Section("Invoices") {
                    if invoices.isEmpty {
                        Text("No invoices yet.").foregroundStyle(Theme.muted)
                    }
                    ForEach(invoices) { invoice in
                        NavigationLink(value: invoice) { InvoiceRow(invoice: invoice, showTenant: false) }
                    }
                }
            } else {
                EmptyStateView(title: "Lease not found", message: "Pull to refresh on the Leases tab.")
            }
        }
        .screenBackground()
        .navigationTitle(lease?.tenant ?? "Lease")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Invoice.self) { InvoiceDetailView(invoiceId: $0.id) }
    }

    private func issueNext() async {
        isIssuing = true
        message = nil
        errorMessage = nil
        defer { isIssuing = false }
        do {
            let invoice = try await app.api.issueNextInvoice(leaseId: leaseId)
            store.replace(invoice)
            message = "Invoice for \(invoice.billingPeriodLabel) issued: \(Money.etb(invoice.amount))."
        } catch {
            errorMessage = app.handle(error)
        }
    }
}
