import Foundation

enum Money {
    /// "ETB 60,375" or "ETB 3,852.50" (cents only when there are any).
    static func etb(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        return "ETB " + (formatter.string(from: NSNumber(value: value)) ?? String(value))
    }
}

enum CalendarSystem: String, CaseIterable, Identifiable {
    case gregorian = "Gregorian"
    case ethiopian = "Ethiopian"
    var id: String { rawValue }
    var shortName: String { self == .gregorian ? "G.C." : "E.C." }
}

/// Ethiopian (Amete Mihret) calendar, the same conversion as the backend and web app: 12 months of 30 days
/// plus Pagume (5, or 6 before a Gregorian leap year), via the Julian day number.
enum EthiopianCalendar {
    private static let epochOffset = 1_723_856

    static let monthNames = [
        "Meskerem", "Tikimt", "Hidar", "Tahsas", "Tir", "Yekatit",
        "Megabit", "Miyazya", "Ginbot", "Sene", "Hamle", "Nehase", "Pagume"
    ]

    static func gregorianToJDN(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    static func jdnToGregorian(_ jdn: Int) -> (year: Int, month: Int, day: Int) {
        let a = jdn + 32044
        let b = (4 * a + 3) / 146097
        let c = a - (146097 * b) / 4
        let d = (4 * c + 3) / 1461
        let e = c - (1461 * d) / 4
        let m = (5 * e + 2) / 153
        return (100 * b + d - 4800 + m / 10, m + 3 - 12 * (m / 10), e - (153 * m + 2) / 5 + 1)
    }

    static func fromGregorian(year: Int, month: Int, day: Int) -> (year: Int, month: Int, day: Int) {
        let jdn = gregorianToJDN(year: year, month: month, day: day)
        let r = (jdn - epochOffset) % 1461
        let n = (r % 365) + 365 * (r / 1460)
        return (4 * ((jdn - epochOffset) / 1461) + r / 365 - r / 1460, n / 30 + 1, n % 30 + 1)
    }

    static func toGregorian(year: Int, month: Int, day: Int) -> (year: Int, month: Int, day: Int) {
        jdnToGregorian(epochOffset + 365 + 365 * (year - 1) + year / 4 + 30 * month + day - 31)
    }
}

enum AppDate {
    /// "yyyy-MM-dd" → parts, or nil.
    static func parts(_ iso: String?) -> (year: Int, month: Int, day: Int)? {
        guard let iso, iso.count >= 10 else { return nil }
        let pieces = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        return (pieces[0], pieces[1], pieces[2])
    }

    /// "30 Nov 2026" or "Hidar 21, 2019 E.C."
    static func format(_ iso: String?, calendar: CalendarSystem) -> String {
        guard let p = parts(iso) else { return iso ?? "—" }
        if calendar == .ethiopian {
            let ec = EthiopianCalendar.fromGregorian(year: p.year, month: p.month, day: p.day)
            return "\(EthiopianCalendar.monthNames[ec.month - 1]) \(ec.day), \(ec.year) E.C."
        }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(p.day) \(months[p.month - 1]) \(p.year)"
    }

    /// Today in Addis Ababa (UTC+3) as "yyyy-MM-dd".
    static func todayISO() -> String {
        iso(from: Date())
    }

    static func iso(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Africa/Addis_Ababa")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(from iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Africa/Addis_Ababa")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(iso.prefix(10)))
    }
}
