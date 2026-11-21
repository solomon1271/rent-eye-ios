import Foundation

extension APIClient {
    // MARK: Tenant portal (signed in as a tenant)

    /// "?leaseId=…" when the tenant picked one of several leases; the server uses their main lease otherwise.
    private static func leaseQuery(_ leaseId: String?) -> String {
        guard let leaseId, !leaseId.isEmpty else { return "" }
        return "?leaseId=\(encode(leaseId))"
    }

    func tenantLeases() async throws -> [Lease] {
        try await get("api/tenant-portal/leases")
    }

    func tenantOverview(leaseId: String?) async throws -> TenantOverview {
        try await get("api/tenant-portal/overview" + Self.leaseQuery(leaseId))
    }

    func tenantBilling(leaseId: String?) async throws -> TenantBilling {
        try await get("api/tenant-portal/billing" + Self.leaseQuery(leaseId))
    }

    func submitTenantPayment(_ submission: TenantPaymentSubmission) async throws -> Payment {
        try await post("api/tenant-portal/payments", body: submission)
    }

    func createMaintenanceRequest(_ request: CreateMaintenanceRequest, leaseId: String?) async throws -> MaintenanceTicket {
        try await post("api/tenant-portal/maintenance" + Self.leaseQuery(leaseId), body: request)
    }

    func updateTenantProfile(_ request: UpdateTenantProfileRequest, leaseId: String?) async throws -> TenantProfile {
        try await put("api/tenant-portal/profile" + Self.leaseQuery(leaseId), body: request)
    }

    // MARK: Inviting tenants (signed in as landlord staff)

    func createTenantInvite(_ request: CreateTenantInviteRequest) async throws -> TenantInviteResult {
        try await post("api/tenant-invites", body: request)
    }

    func leaseAccess(leaseId: String) async throws -> [LeaseAccessEntry] {
        try await get("api/leases/\(Self.encode(leaseId))/access")
    }

    func grantLeaseAccess(leaseId: String, email: String) async throws -> LeaseAccessEntry {
        try await post("api/leases/\(Self.encode(leaseId))/access", body: GrantLeaseAccessRequest(email: email))
    }
}
