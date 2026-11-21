import Foundation

// Shapes returned by the Rent Eye backend (JSON in camelCase). Optional where older records may lack a field.

struct AuthSession: Codable, Equatable {
    let userId: String
    let workspaceId: String
    let fullName: String
    let role: String
    let email: String
    let workspaceName: String
    let workspaceSlug: String
    let accessToken: String
    let sessionExpiresAtUtc: String?
    let tenantLeaseId: String?
    let isPlatformAdmin: Bool?

    var isAdministrator: Bool { role.localizedCaseInsensitiveContains("admin") }
    var isTenant: Bool { role.localizedCaseInsensitiveContains("tenant") }
    var isPlatform: Bool { isPlatformAdmin == true }
    var roleLabel: String { isPlatform ? "Platform admin" : (isAdministrator ? "Admin" : "Staff") }
}

struct LoginResult: Decodable {
    let status: String
    let message: String
    let challengeId: String?
    let session: AuthSession?
}

struct Property: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let area: String
    let address: String
    let propertyType: String
    let units: Int
    let occupied: Int
    let vacant: Int
    let occupancyRate: String
}

struct PropertyUnit: Decodable, Identifiable, Hashable {
    let propertyId: String
    let propertyName: String
    let unit: String
    let status: String
    let tenant: String
    let monthlyRent: Double
    let leaseEnd: String
    let floor: String?

    var id: String { "\(propertyId):\(unit)" }
}

struct Lease: Decodable, Identifiable, Hashable {
    let id: String
    let propertyId: String
    let propertyName: String
    let unit: String
    let tenant: String
    let rent: Double
    let leaseStart: String
    let leaseEnd: String
    let deposit: Double
    let manager: String
    let status: String
    let billingCycle: String?
    let billingIntervalMonths: Int?
    let serviceCharge: Double?
    let taxRate: Double?
    let billingCalendar: String?

    var scheduleDescription: String {
        let base: String
        switch billingCycle ?? "Monthly" {
        case "Quarterly": base = "Every 3 months"
        case "Semiannual": base = "Every 6 months"
        case "Annual": base = "Every year"
        case "OneTime": base = "Once for the whole lease"
        case "Custom": base = "Every \(billingIntervalMonths ?? 1) months"
        default: base = "Every month"
        }
        return billingCalendar == "Ethiopian" && billingCycle != "OneTime" ? base + " · Ethiopian months" : base
    }
}

struct Invoice: Decodable, Identifiable, Hashable {
    let id: String
    let leaseId: String
    let propertyId: String
    let propertyName: String
    let unit: String
    let tenant: String
    let manager: String
    let amount: Double
    let amountPaid: Double
    let balanceDue: Double
    let billingPeriodStart: String
    let billingPeriodEnd: String
    let billingPeriodLabel: String
    let issuedDate: String
    let dueDate: String
    let status: String
    let daysLate: Int
    let rentAmount: Double?
    let serviceCharge: Double?
    let taxAmount: Double?
    let kind: String?
    let utilityType: String?

    var isOpen: Bool { balanceDue > 0 }

    /// Rent / service / tax lines; older invoices only have a total.
    var lines: [(label: String, amount: Double)] {
        let rent = rentAmount ?? 0, service = serviceCharge ?? 0, tax = taxAmount ?? 0
        guard rent + service + tax > 0 else { return [("Rent", amount)] }
        var result: [(label: String, amount: Double)] = [(kind == "Rent" || kind == nil ? "Rent" : billingPeriodLabel, rent)]
        if service > 0 { result.append((kind == "Utility" ? "Service fee" : "Service charge", service)) }
        if tax > 0 { result.append(("Tax", tax)) }
        return result
    }
}

struct Payment: Codable, Identifiable, Hashable {
    let id: String
    let invoiceId: String
    let leaseId: String
    let propertyId: String
    let propertyName: String
    let unit: String
    let tenant: String
    let manager: String
    let amount: Double
    let appliedAmount: Double
    let creditRemaining: Double
    let paymentDate: String
    let method: String
    let reference: String
    let note: String
    var status: String? = nil
    var submittedBy: String? = nil
    var reviewedBy: String? = nil
    var reviewNote: String? = nil

    var isPending: Bool { status == "Pending" }
    var isApproved: Bool { (status ?? "Approved") == "Approved" }
}

struct PeriodReport: Decodable {
    let from: String
    let to: String
    let totalBilled: Double
    let totalCollected: Double
    let totalOutstanding: Double
    let totalPendingReview: Double
    let billed: [Invoice]
    let collected: [Payment]
    let outstanding: [Invoice]
    let pendingReview: [Payment]
}

struct ReviewRequest: Encodable { let note: String? }
struct LoginRequest: Encodable { let emailOrPhone: String; let password: String; let workspaceSlug: String? }
struct VerifyMfaRequest: Encodable { let challengeId: String; let code: String }
struct EmptyBody: Encodable {}
