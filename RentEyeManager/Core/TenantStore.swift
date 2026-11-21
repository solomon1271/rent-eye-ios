import Foundation
import Observation

/// Everything the tenant screens show, for the lease the tenant is looking at.
@MainActor
@Observable
final class TenantStore {
    var leases: [Lease] = []
    var lease: Lease?
    var invoices: [Invoice] = []
    var payments: [Payment] = []
    var tickets: [MaintenanceTicket] = []
    var profile: TenantProfile?
    var isLoading = false
    var errorMessage: String?
    /// True when the account isn't linked to any lease yet (the landlord needs to give access).
    var hasNoLease = false
    private(set) var loadedOnce = false

    /// The lease picked in the switcher, remembered between launches (like the website does).
    var selectedLeaseId: String? {
        didSet { UserDefaults.standard.set(selectedLeaseId, forKey: "tenantLeaseId") }
    }

    init() {
        selectedLeaseId = UserDefaults.standard.string(forKey: "tenantLeaseId")
    }

    var openInvoices: [Invoice] {
        invoices.filter(\.isOpen).sorted { $0.dueDate < $1.dueDate }
    }

    var balanceDue: Double { invoices.reduce(0) { $0 + max($1.balanceDue, 0) } }

    var overdueInvoices: [Invoice] { openInvoices.filter { $0.daysLate > 0 } }

    /// The next bill to pay: the oldest one still open.
    var nextInvoice: Invoice? { openInvoices.first }

    var pendingPayments: [Payment] { payments.filter(\.isPending) }

    /// Payments already sent for this invoice and still waiting for the landlord.
    func pendingAmount(for invoice: Invoice) -> Double {
        payments.filter { $0.isPending && $0.invoiceId == invoice.id }.reduce(0) { $0 + $1.amount }
    }

    func load(using app: AppState) async {
        isLoading = true
        defer { isLoading = false }
        let api = app.api
        do {
            leases = try await api.tenantLeases()
            if leases.isEmpty {
                hasNoLease = true
                lease = nil; invoices = []; payments = []; tickets = []
                errorMessage = nil
                loadedOnce = true
                return
            }
            hasNoLease = false
            // A remembered lease the tenant can no longer open falls back to their main lease.
            if let selected = selectedLeaseId, !leases.contains(where: { $0.id == selected }) {
                selectedLeaseId = nil
            }
            let leaseId = selectedLeaseId
            async let billing = api.tenantBilling(leaseId: leaseId)
            async let overview = api.tenantOverview(leaseId: leaseId)
            let (billingResult, overviewResult) = try await (billing, overview)
            lease = billingResult.lease
            invoices = billingResult.invoices
            payments = billingResult.payments.sorted { $0.paymentDate > $1.paymentDate }
            tickets = overviewResult.maintenanceTickets
            profile = overviewResult.profile
            errorMessage = nil
            loadedOnce = true
        } catch let error as APIError where error.status == 404 {
            hasNoLease = true
            errorMessage = nil
            loadedOnce = true
        } catch {
            errorMessage = app.handle(error)
        }
    }

    func loadIfNeeded(using app: AppState) async {
        if !loadedOnce { await load(using: app) }
    }

    func select(leaseId: String, using app: AppState) async {
        selectedLeaseId = leaseId
        await load(using: app)
    }

    func reset() {
        leases = []; lease = nil; invoices = []; payments = []; tickets = []; profile = nil
        errorMessage = nil; hasNoLease = false; loadedOnce = false
    }
}
