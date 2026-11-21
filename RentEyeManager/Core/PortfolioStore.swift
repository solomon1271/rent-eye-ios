import Foundation
import Observation

/// Everything the screens show, loaded once and refreshed on pull-to-refresh or after a change.
@MainActor
@Observable
final class PortfolioStore {
    var properties: [Property] = []
    var units: [PropertyUnit] = []
    var leases: [Lease] = []
    var invoices: [Invoice] = []
    var payments: [Payment] = []
    var isLoading = false
    var errorMessage: String?
    private(set) var loadedOnce = false

    var pendingPayments: [Payment] { payments.filter(\.isPending).sorted { $0.paymentDate < $1.paymentDate } }
    var openInvoices: [Invoice] { invoices.filter(\.isOpen) }
    var occupiedUnits: Int { units.filter { $0.status == "Occupied" }.count }

    func load(using app: AppState) async {
        isLoading = true
        defer { isLoading = false }
        let api = app.api
        do {
            async let properties = api.properties()
            async let units = api.units()
            async let leases = api.leases()
            async let invoices = api.invoices()
            async let payments = api.payments()
            self.properties = try await properties.sorted { $0.name < $1.name }
            self.units = try await units
            self.leases = try await leases
            self.invoices = try await invoices
            self.payments = try await payments
            errorMessage = nil
            loadedOnce = true
        } catch {
            errorMessage = app.handle(error)
        }
    }

    func loadIfNeeded(using app: AppState) async {
        if !loadedOnce { await load(using: app) }
    }

    func replace(_ payment: Payment) {
        payments.removeAll { $0.id == payment.id }
        payments.append(payment)
    }

    func replace(_ invoice: Invoice) {
        invoices.removeAll { $0.id == invoice.id }
        invoices.append(invoice)
    }

    /// Invoices change on the server when a payment is approved; re-read them.
    func reloadInvoices(using app: AppState) async {
        if let fresh = try? await app.api.invoices() { invoices = fresh }
    }

    func reset() {
        properties = []; units = []; leases = []; invoices = []; payments = []
        loadedOnce = false; errorMessage = nil
    }
}
