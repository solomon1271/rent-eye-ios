import Foundation

// Platform admin (organisations) and invitation shapes returned by the Rent Eye backend.

struct PlatformOrganization: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let slug: String
    let createdAtUtc: String
    let accountStatus: String
    let subscriptionStatus: String
    let subscriptionPlan: String
    let subscriptionRenewsAtUtc: String?
    let activeUserCount: Int
    let propertyCount: Int
    let administratorName: String?
    let administratorEmail: String?
    let administratorEmailVerified: Bool
    let hasPendingInvite: Bool
    let pendingInviteExpiresAtUtc: String?

    /// "Waiting for owner" until the invited administrator finishes setup.
    var isWaitingForOwner: Bool { accountStatus == "pending" || hasPendingInvite }

    var statusLabel: String {
        if accountStatus == "pending" { return "Waiting for owner" }
        return accountStatus.prefix(1).uppercased() + accountStatus.dropFirst()
    }

    var statusTone: StatusPill.Tone {
        switch accountStatus {
        case "active": .good
        case "pending": .warning
        case "suspended", "cancelled": .danger
        default: .neutral
        }
    }
}

enum PlatformOptions {
    static let accountStatuses = ["pending", "active", "suspended", "cancelled"]
    static let plans = ["standard", "professional", "enterprise"]
    static let subscriptionStatuses = ["trial", "active", "past_due", "expired", "cancelled"]

    static func label(_ value: String) -> String {
        let spaced = value.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// "Abebe Properties PLC" → "abebe-properties-plc" (what the server accepts).
    static func slug(from name: String) -> String {
        let lowered = name.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        var result = ""
        var lastWasHyphen = false
        for character in lowered {
            if character.isASCII && (character.isLetter || character.isNumber) {
                result.append(character)
                lastWasHyphen = false
            } else if !lastWasHyphen && !result.isEmpty {
                result.append("-")
                lastWasHyphen = true
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return String(result.prefix(48))
    }
}

struct CreateOrganizationRequest: Encodable {
    let organizationName: String
    let workspaceSlug: String
    let administratorFullName: String
    let administratorEmail: String
    let administratorPhone: String
    let subscriptionPlan: String
    let subscriptionStatus: String
    let subscriptionRenewsAtUtc: String?
}

struct CreateOrganizationResult: Decodable {
    let message: String
    let workspaceId: String
    let administratorEmail: String
    let inviteToken: String
    let expiresAtUtc: String
    let deliveryMode: String
}

struct UpdateOrganizationRequest: Encodable {
    let organizationName: String?
    let administratorFullName: String?
    let administratorEmail: String?
    let administratorPhone: String?
    let accountStatus: String?
    let subscriptionStatus: String?
    let subscriptionPlan: String?
    let subscriptionRenewsAtUtc: String?
}

struct UpdateOrganizationResult: Decodable {
    let organization: PlatformOrganization
    let message: String
    let invitePath: String?
}

struct ResendInviteResult: Decodable {
    let message: String
    let inviteToken: String
    let expiresAtUtc: String
    let deliveryMode: String
}

struct ResetAccountsResult: Decodable {
    let message: String
    let removedUserCount: Int
}

struct MessageResult: Decodable { let message: String }

/// An invitation to share: the code the person types into the app.
struct InviteToShare: Identifiable {
    let organizationName: String
    let personName: String
    let email: String
    let code: String
    let expiresAtUtc: String?
    var id: String { code }

    var shareText: String {
        """
        Hi \(personName), you're invited to manage \(organizationName) on Rent Eye.

        1. Install the Rent Eye app.
        2. Tap "I have an invitation" on the sign-in screen.
        3. Enter this code: \(code)

        Use this email when you set up: \(email)
        """
    }
}

// MARK: - Accepting an invitation

enum InviteKind: String {
    case organizationOwner, staff

    var acceptPath: String {
        switch self {
        case .organizationOwner: "api/platform/organization-invites/accept"
        case .staff: "api/staff/auth/accept-invite"
        }
    }

    var roleDescription: String {
        switch self {
        case .organizationOwner: "administrator"
        case .staff: "staff member"
        }
    }
}

struct OrganizationInvitePreview: Decodable {
    let organizationName: String
    let fullName: String
    let email: String
    let phone: String
    let expiresAtUtc: String
}

struct StaffInvitePreview: Decodable {
    let workspaceName: String
    let fullName: String
    let email: String
    let phone: String
    let expiresAtUtc: String
}

/// What the app shows after looking up an invitation code.
struct InviteDetails {
    let kind: InviteKind
    let code: String
    let organizationName: String
    let fullName: String
    let email: String
    let phone: String
}

struct AcceptInviteRequest: Encodable {
    let inviteToken: String
    let fullName: String
    let email: String
    let phone: String
    let password: String
}

struct RegisterResult: Decodable {
    let message: String
    let email: String
}
