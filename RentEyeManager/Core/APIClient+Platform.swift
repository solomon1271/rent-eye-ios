import Foundation

extension APIClient {
    // MARK: Platform admin

    func organizations() async throws -> [PlatformOrganization] {
        try await get("api/platform/organizations")
    }

    func createOrganization(_ request: CreateOrganizationRequest) async throws -> CreateOrganizationResult {
        try await post("api/platform/organizations", body: request)
    }

    func updateOrganization(id: String, _ request: UpdateOrganizationRequest) async throws -> UpdateOrganizationResult {
        try await put("api/platform/organizations/\(Self.encode(id))", body: request)
    }

    func resendInvite(organizationId: String) async throws -> ResendInviteResult {
        try await post("api/platform/organizations/\(Self.encode(organizationId))/resend-invite", body: EmptyBody())
    }

    func resetAccounts(organizationId: String) async throws -> ResetAccountsResult {
        try await post("api/platform/organizations/\(Self.encode(organizationId))/reset-accounts", body: EmptyBody())
    }

    func deleteOrganization(id: String) async throws -> MessageResult {
        try await delete("api/platform/organizations/\(Self.encode(id))")
    }

    // MARK: Invitations (no sign-in needed)

    /// Looks the code up as an organisation-owner invitation first, then as a staff invitation.
    func lookUpInvite(code: String) async throws -> InviteDetails {
        do {
            let invite: OrganizationInvitePreview = try await get("api/platform/organization-invites/\(Self.encode(code))")
            return InviteDetails(kind: .organizationOwner, code: code, organizationName: invite.organizationName,
                                 fullName: invite.fullName, email: invite.email, phone: invite.phone)
        } catch let error as APIError where error.status == 404 {
            do {
                let invite: StaffInvitePreview = try await get("api/staff/auth/invites/\(Self.encode(code))")
                return InviteDetails(kind: .staff, code: code, organizationName: invite.workspaceName,
                                     fullName: invite.fullName, email: invite.email, phone: invite.phone)
            } catch let staffError as APIError where staffError.status == 404 || staffError.status == 400 {
                throw APIError(status: 404, message: "That invitation code isn't valid or has expired. Ask for a new one.")
            }
        }
    }

    func acceptInvite(_ kind: InviteKind, _ request: AcceptInviteRequest) async throws -> RegisterResult {
        try await post(kind.acceptPath, body: request)
    }
}

/// Pulls the invitation code out of whatever was pasted: the bare code, or a link ending in ?invite=CODE.
enum InviteCode {
    static func extract(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Codes are 32 letters/digits (0-9, a-f). Find one even inside a whole pasted message.
        let lowered = trimmed.lowercased()
        if let pattern = try? Regex("[0-9a-f]{32}"), let match = lowered.firstMatch(of: pattern) {
            return String(lowered[match.range])
        }
        if let components = URLComponents(string: trimmed),
           let value = components.queryItems?.first(where: { $0.name == "invite" })?.value {
            return value.lowercased()
        }
        if let range = trimmed.range(of: "invite=") {
            return String(trimmed[range.upperBound...]
                .prefix { $0.isLetter || $0.isNumber })
                .lowercased()
        }
        // A 32-character code may arrive with spaces or line breaks from a chat app.
        let compact = trimmed.filter { $0.isLetter || $0.isNumber }
        return compact.lowercased()
    }
}
