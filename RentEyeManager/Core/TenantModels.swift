import Foundation

// Shapes for the tenant side of the app (tenant portal endpoints) and for inviting tenants.

struct TenantProfile: Codable, Hashable {
    var id: String
    var name: String
    var phone: String
    var email: String
    var currentAddress: String
    var occupation: String
    var employer: String
    var emergencyContactName: String
    var emergencyContactPhone: String
    var tenantType: String? = nil
    var companyName: String? = nil
    var tin: String? = nil
}

struct MaintenanceTicket: Decodable, Identifiable, Hashable {
    let id: String
    let propertyName: String?
    let unit: String?
    let issue: String
    let category: String?
    let priority: String?
    let status: String
    let reportedDate: String?
    let targetDate: String?
    let assignedTo: String?
    let accessWindow: String?
    let nextAction: String?
    let resolutionNote: String?

    var isClosed: Bool {
        ["resolved", "closed", "completed", "done"].contains(status.lowercased())
    }

    var statusTone: StatusPill.Tone {
        if isClosed { return .good }
        switch status.lowercased() {
        case "open", "new", "reported": return .warning
        default: return .neutral
        }
    }
}

struct TenantOverview: Decodable {
    let profile: TenantProfile?
    let currentLease: Lease?
    let currentInvoice: Invoice?
    let recentPayments: [Payment]
    let maintenanceTickets: [MaintenanceTicket]
}

struct TenantBilling: Decodable {
    let lease: Lease
    let invoices: [Invoice]
    let payments: [Payment]
}

struct TenantPaymentSubmission: Encodable {
    let invoiceId: String
    let provider: String
    let amount: Double
    let paymentDate: String
    let reference: String
    let note: String?
}

struct CreateMaintenanceRequest: Encodable {
    let issue: String
    let category: String
    let priority: String
    let accessWindow: String?
}

struct UpdateTenantProfileRequest: Encodable {
    let name: String
    let phone: String
    let email: String
    let currentAddress: String
    let occupation: String
    let employer: String
    let emergencyContactName: String
    let emergencyContactPhone: String
}

enum TenantOptions {
    /// Same list as the website's "I paid" form.
    static let providers = ["CBE Transfer", "telebirr", "Chapa"]
    static let categories = ["Plumbing", "Electrical", "Appliance", "Access", "General Repair"]
    static let priorities = ["Standard", "High", "Urgent"]

    static func referenceHint(for provider: String) -> String {
        provider == "telebirr" ? "e.g. CK12AB3XYZ" : "e.g. FT26324ABCDE"
    }
}

// MARK: - Inviting tenants (landlord side)

struct CreateTenantInviteRequest: Encodable {
    let fullName: String
    let email: String
    let phone: String
    let leaseId: String?
    let propertyId: String?
    let unit: String?
}

struct TenantInviteResult: Decodable {
    let message: String
    let workspaceName: String
    let workspaceSlug: String
    let email: String
    let inviteToken: String
    let invitePath: String
    let expiresAtUtc: String
    let deliveryMode: String
    let previewInviteUrl: String?
}

struct GrantLeaseAccessRequest: Encodable { let email: String }

struct LeaseAccessEntry: Decodable, Identifiable, Hashable {
    let userId: String
    let fullName: String
    let email: String
    let source: String
    var id: String { userId }
}

struct TenantInvitePreview: Decodable {
    let workspaceName: String
    let fullName: String
    let email: String
    let phone: String
    let unit: String?
    let expiresAtUtc: String
}
