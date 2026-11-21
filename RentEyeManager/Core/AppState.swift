import Foundation
import Observation
import Security

/// Signed-in session, server address and display calendar, shared by every screen.
@MainActor
@Observable
final class AppState {
    static let defaultServer = "http://localhost:5050"

    private(set) var session: AuthSession?
    private(set) var serverAddress: String

    init() {
        serverAddress = UserDefaults.standard.string(forKey: "serverAddress") ?? Self.defaultServer
        session = SessionStore.load()
    }

    var api: APIClient { APIClient(baseURL: serverAddress, token: session?.accessToken) }

    func setServerAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        serverAddress = trimmed.isEmpty ? Self.defaultServer : trimmed
        UserDefaults.standard.set(serverAddress, forKey: "serverAddress")
    }

    /// Returns a challenge id when the server asks for the emailed 6-digit code.
    func signIn(email: String, password: String) async throws -> String? {
        let result: LoginResult = try await APIClient(baseURL: serverAddress, token: nil)
            .post("api/auth/login", body: LoginRequest(emailOrPhone: email, password: password, workspaceSlug: nil))
        if let session = result.session {
            try accept(session)
            return nil
        }
        if result.status == "mfa_required", let challengeId = result.challengeId {
            return challengeId
        }
        throw APIError(status: 0, message: result.message)
    }

    func verifyCode(challengeId: String, code: String) async throws {
        let session: AuthSession = try await APIClient(baseURL: serverAddress, token: nil)
            .post("api/auth/mfa/verify", body: VerifyMfaRequest(challengeId: challengeId, code: code))
        try accept(session)
    }

    private func accept(_ session: AuthSession) throws {
        if session.isTenant || session.isPlatformAdmin == true {
            // End that session on the server; this app is for property managers.
            let token = session.accessToken
            Task { try? await APIClient(baseURL: serverAddress, token: token).postIgnoringResult("api/auth/logout", body: EmptyBody()) }
            throw APIError(status: 403, message: session.isTenant
                ? "This app is for landlords and staff. Tenants will get their own app."
                : "The platform admin account works on the website. Sign in with an organisation account.")
        }
        self.session = session
        SessionStore.save(session)
    }

    /// Confirms the saved session is still valid (e.g. after a restart).
    func validateSession() async {
        guard session != nil else { return }
        do {
            let _: AuthSession = try await api.get("api/auth/me")
        } catch let error as APIError where error.isUnauthorized {
            signOutLocally()
        } catch {
            // Offline or server asleep: keep the session and let screens retry.
        }
    }

    func signOut() async {
        try? await api.postIgnoringResult("api/auth/logout", body: EmptyBody())
        signOutLocally()
    }

    func signOutLocally() {
        session = nil
        SessionStore.clear()
    }

    /// Call from screens when a request fails; a 401 means the session ended.
    func handle(_ error: Error) -> String {
        if let apiError = error as? APIError, apiError.isUnauthorized {
            signOutLocally()
        }
        return error.localizedDescription
    }
}

/// Keeps the session in the Keychain so the token isn't stored in plain files.
enum SessionStore {
    private static let service = "com.renteye.manager"
    private static let account = "session"

    static func save(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
