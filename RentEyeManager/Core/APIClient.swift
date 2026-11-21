import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

private struct ErrorBody: Decodable {
    let message: String?
    let errors: [String: [String]]?
}

/// Talks to the Rent Eye backend with the signed-in user's bearer token.
struct APIClient {
    let baseURL: String
    let token: String?

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try decode(try await send("GET", path, body: nil))
    }

    func post<T: Decodable>(_ path: String, body: some Encodable, as type: T.Type = T.self) async throws -> T {
        try decode(try await send("POST", path, body: try JSONEncoder().encode(body)))
    }

    func postIgnoringResult(_ path: String, body: some Encodable) async throws {
        _ = try await send("POST", path, body: try JSONEncoder().encode(body))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError(status: 0, message: "The server sent something this app doesn't understand. Update the app or check the server address.")
        }
    }

    private func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw APIError(status: 0, message: "The server address isn't valid. Check it in Settings.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        // Render's free plan can take up to a minute to wake the server.
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(status: 0, message: "Can't reach the server. Check your internet connection and the server address, then try again.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let parsed = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let fieldMessage = parsed?.errors?.values.flatMap { $0 }.first
            let message = fieldMessage ?? parsed?.message ?? (status == 401 ? "Your session has ended. Sign in again." : "Request failed (\(status)).")
            throw APIError(status: status, message: message)
        }
        return data
    }
}

extension APIClient {
    func properties() async throws -> [Property] { try await get("api/properties") }
    func units() async throws -> [PropertyUnit] { try await get("api/property-units") }
    func leases() async throws -> [Lease] { try await get("api/leases") }
    func invoices() async throws -> [Invoice] { try await get("api/invoices") }
    func payments() async throws -> [Payment] { try await get("api/payments") }

    func issueNextInvoice(leaseId: String) async throws -> Invoice {
        try await post("api/leases/\(Self.encode(leaseId))/invoices/next", body: EmptyBody())
    }

    func approve(paymentId: String) async throws -> Payment {
        try await post("api/payments/\(Self.encode(paymentId))/approve", body: ReviewRequest(note: nil))
    }

    func reject(paymentId: String, reason: String) async throws -> Payment {
        try await post("api/payments/\(Self.encode(paymentId))/reject", body: ReviewRequest(note: reason))
    }

    func recordPayment(_ payment: Payment) async throws -> Payment {
        try await post("api/payments", body: payment)
    }

    func periodReport(from: String, to: String) async throws -> PeriodReport {
        try await get("api/reports/period?from=\(from)&to=\(to)")
    }

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? value
    }
}
