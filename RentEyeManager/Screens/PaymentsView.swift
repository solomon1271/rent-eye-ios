import SwiftUI

struct PaymentsView: View {
    @Environment(AppState.self) private var app
    @Environment(PortfolioStore.self) private var store
    @State private var rejecting: Payment?
    @State private var reason = ""
    @State private var busyId: String?
    @State private var errorMessage: String?

    private var recent: [Payment] {
        store.payments.filter { !$0.isPending }.sorted { $0.paymentDate > $1.paymentDate }.prefix(40).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }

                Section {
                    if store.pendingPayments.isEmpty {
                        Text("Nothing to review. Payments tenants send from their app appear here.")
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(store.pendingPayments) { payment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(Money.etb(payment.amount)).font(.title3.weight(.bold))
                                Spacer()
                                StatusPill.payment(payment.status)
                            }
                            Text("\(payment.method) · Ref \(payment.reference)")
                                .font(.subheadline.monospaced())
                                .textSelection(.enabled)
                            HStack(spacing: 4) {
                                Text("\(payment.tenant), \(payment.propertyName) \(payment.unit) · paid")
                                DateLabel(iso: payment.paymentDate)
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                            if !payment.note.isEmpty {
                                Text("“\(payment.note)”").font(.caption).foregroundStyle(Theme.muted)
                            }
                            HStack {
                                Button("Reject", role: .destructive) {
                                    reason = ""
                                    rejecting = payment
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button {
                                    Task { await approve(payment) }
                                } label: {
                                    if busyId == payment.id { ProgressView() } else { Text("Approve").frame(minWidth: 90) }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .disabled(busyId != nil)
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Waiting for review")
                } footer: {
                    if !store.pendingPayments.isEmpty {
                        Text("Find each reference in your bank, telebirr or Chapa records before approving it.")
                    }
                }

                Section("Recent") {
                    ForEach(recent) { payment in PaymentRow(payment: payment, showTenant: true) }
                }
            }
            .screenBackground()
            .navigationTitle("Payments")
            .refreshable { await store.load(using: app) }
            .task { await store.loadIfNeeded(using: app) }
            .alert("Reject this payment?", isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } })) {
                TextField("Reason the tenant will see", text: $reason)
                Button("Reject", role: .destructive) {
                    if let payment = rejecting { Task { await reject(payment) } }
                }
                Button("Cancel", role: .cancel) { rejecting = nil }
            } message: {
                Text("For example: no transfer with this reference on our statement.")
            }
        }
    }

    private func approve(_ payment: Payment) async {
        busyId = payment.id
        defer { busyId = nil }
        do {
            store.replace(try await app.api.approve(paymentId: payment.id))
            await store.reloadInvoices(using: app)
            errorMessage = nil
        } catch {
            errorMessage = app.handle(error)
        }
    }

    private func reject(_ payment: Payment) async {
        let trimmed = reason.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            errorMessage = "Give a short reason so the tenant knows why."
            return
        }
        busyId = payment.id
        defer { busyId = nil; rejecting = nil }
        do {
            store.replace(try await app.api.reject(paymentId: payment.id, reason: trimmed))
            errorMessage = nil
        } catch {
            errorMessage = app.handle(error)
        }
    }
}

struct PaymentRow: View {
    let payment: Payment
    var showTenant = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Money.etb(payment.amount)).font(.subheadline.weight(.semibold))
                Spacer()
                StatusPill.payment(payment.status)
            }
            HStack(spacing: 4) {
                if showTenant { Text("\(payment.tenant) ·") }
                Text("\(payment.method) · \(payment.reference) ·")
                DateLabel(iso: payment.paymentDate)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .lineLimit(2)
            if payment.status == "Rejected", let note = payment.reviewNote, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }
}
