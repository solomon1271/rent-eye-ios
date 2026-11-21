import SwiftUI

/// The "Highland" palette shared with the web app: deep highland green, Meskel-flower yellow, cool off-white.
enum Theme {
    static let brand = Color(hex: 0x155E54)
    static let brandDark = Color(hex: 0x0E433C)
    static let brandDeep = Color(hex: 0x0C2F2B)
    static let brandSoft = Color(hex: 0xE4EFEC)
    static let accent = Color(hex: 0xE8B23A)
    static let accentSoft = Color(hex: 0xFBF1D9)
    static let background = Color(hex: 0xF5F7F4)
    static let ink = Color(hex: 0x1C2530)
    static let muted = Color(hex: 0x5A6472)
    static let ok = Color(hex: 0x1E7B4F)
    static let warn = Color(hex: 0x9A6100)
    static let danger = Color(hex: 0xB42318)
    static let tibebRed = Color(hex: 0xC8463D)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The woven tibeb band: the app's one decorative signature, used as a thin stripe.
struct TibebBand: View {
    var height: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let pattern: [(Color, CGFloat)] = [
                (Theme.accent, 14), (Theme.brandDeep, 3), (Theme.tibebRed, 6),
                (Theme.brandDeep, 3), (.white, 3), (Theme.brandDeep, 3)
            ]
            var x: CGFloat = 0
            while x < size.width {
                for (color, width) in pattern {
                    context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(color))
                    x += width
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// Status pill used for invoices and payments.
struct StatusPill: View {
    let text: String
    let tone: Tone

    enum Tone { case good, warning, danger, neutral }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .good: Theme.ok
        case .warning: Theme.warn
        case .danger: Theme.danger
        case .neutral: Theme.muted
        }
    }

    private var background: Color {
        switch tone {
        case .good: Color(hex: 0xE6F4EC)
        case .warning: Theme.accentSoft
        case .danger: Color(hex: 0xFDECEA)
        case .neutral: Color(hex: 0xECEFF2)
        }
    }
}

extension StatusPill {
    /// Invoice status as stored by the server: Paid, Due Soon, Partially Paid, Overdue.
    static func invoice(_ status: String) -> StatusPill {
        switch status {
        case "Paid": StatusPill(text: "Paid", tone: .good)
        case "Overdue": StatusPill(text: "Overdue", tone: .danger)
        case "Partially Paid": StatusPill(text: "Part paid", tone: .warning)
        default: StatusPill(text: "Due soon", tone: .neutral)
        }
    }

    static func payment(_ status: String?) -> StatusPill {
        switch status ?? "Approved" {
        case "Pending": StatusPill(text: "To review", tone: .warning)
        case "Rejected": StatusPill(text: "Rejected", tone: .danger)
        default: StatusPill(text: "Approved", tone: .good)
        }
    }
}

/// A big number with a label, for summary cards.
struct MetricCard: View {
    let label: String
    let value: String
    var note: String? = nil
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(highlight ? Theme.accent : Theme.brand)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(highlight ? .white : Theme.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(highlight ? .white.opacity(0.75) : Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(highlight ? Theme.brandDeep : .white, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xDCE3DE), lineWidth: highlight ? 0 : 1))
    }
}
