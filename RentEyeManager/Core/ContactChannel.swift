import Foundation

/// How a tenant is reached. WhatsApp, SMS and Telegram open the landlord's own app with the message ready,
/// so nothing is paid for; email is sent by the server once email is set up.
enum ContactChannel: String, CaseIterable, Identifiable {
    case whatsapp, telegram, sms, email

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .telegram: "Telegram"
        case .sms: "SMS"
        case .email: "Email"
        }
    }

    var actionLabel: String {
        switch self {
        case .whatsapp: "Open WhatsApp to send"
        case .telegram: "Open Telegram to send"
        case .sms: "Open Messages to send"
        case .email: "Open Mail to send"
        }
    }

    var systemImage: String {
        switch self {
        case .whatsapp: "message.fill"
        case .telegram: "paperplane.fill"
        case .sms: "bubble.left.fill"
        case .email: "envelope.fill"
        }
    }

    init(serverValue: String?) {
        self = ContactChannel(rawValue: (serverValue ?? "").lowercased()) ?? .email
    }

    /// "0911 22 33 44" → "251911223344" (WhatsApp wants international digits only).
    static func whatsAppNumber(_ phone: String) -> String {
        let digits = phone.filter(\.isNumber)
        if digits.hasPrefix("0") && digits.count == 10 { return "251" + digits.dropFirst() }
        if digits.count == 9 && (digits.hasPrefix("9") || digits.hasPrefix("7")) { return "251" + digits }
        return digits
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? text
    }

    /// A link that opens the right app with the message ready to send.
    func link(phone: String?, email: String?, message: String, webLink: String?, subject: String) -> URL? {
        switch self {
        case .whatsapp:
            return URL(string: "https://wa.me/\(Self.whatsAppNumber(phone ?? ""))?text=\(Self.encode(message))")
        case .sms:
            let number = (phone ?? "").filter { $0.isNumber || $0 == "+" }
            return URL(string: "sms:\(number)&body=\(Self.encode(message))")
        case .telegram:
            let url = webLink ?? "https://t.me"
            return URL(string: "https://t.me/share/url?url=\(Self.encode(url))&text=\(Self.encode(message))")
        case .email:
            return URL(string: "mailto:\(email ?? "")?subject=\(Self.encode(subject))&body=\(Self.encode(message))")
        }
    }
}

extension CharacterSet {
    /// Query values must also escape &, = and + so the message survives intact.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()
}

/// "Not provided" is the server's placeholder for a missing phone.
func isRealPhone(_ phone: String?) -> Bool {
    let value = (phone ?? "").trimmingCharacters(in: .whitespaces)
    return value.count >= 7 && value.lowercased() != "not provided"
}
