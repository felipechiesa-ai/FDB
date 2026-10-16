import Foundation

/// A calendar date known only to year, month, or day precision.
/// Missing parts stay missing: a year-only date never becomes January 1.
public struct PartialDate: Hashable, Sendable, Codable {
    public enum Precision: Int, Sendable, Codable, CaseIterable {
        case year = 1
        case month = 2
        case day = 3
    }

    public let year: Int
    public let month: Int?
    public let day: Int?

    /// Returns nil unless the parts form a real date at their precision.
    public init?(year: Int, month: Int? = nil, day: Int? = nil) {
        guard (1...9999).contains(year) else { return nil }
        if let month {
            guard (1...12).contains(month) else { return nil }
            if let day {
                guard (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
            }
        } else if day != nil {
            return nil
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses the storage form: "YYYY", "YYYY-MM", or "YYYY-MM-DD".
    public init?(storageText: String) {
        let parts = storageText.split(separator: "-", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        switch numbers.count {
        case 1: self.init(year: numbers[0])
        case 2: self.init(year: numbers[0], month: numbers[1])
        case 3: self.init(year: numbers[0], month: numbers[1], day: numbers[2])
        default: return nil
        }
    }

    public var precision: Precision {
        if day != nil { return .day }
        if month != nil { return .month }
        return .year
    }

    /// Sortable yyyymmdd key for the earliest day this date can stand for.
    public var earliestSortKey: Int {
        year * 10_000 + (month ?? 1) * 100 + (day ?? 1)
    }

    /// The storage form: "YYYY", "YYYY-MM", or "YYYY-MM-DD".
    public var storageText: String {
        switch precision {
        case .year: String(format: "%04d", year)
        case .month: String(format: "%04d-%02d", year, month ?? 1)
        case .day: String(format: "%04d-%02d-%02d", year, month ?? 1, day ?? 1)
        }
    }

    /// Localized text. Day precision uses the locale's medium date style.
    public func formatted(locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        switch precision {
        case .year:
            return String(year)
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMMM y")
        case .day:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        }
        guard let date = calendar.date(from: DateComponents(year: year, month: month ?? 1, day: day ?? 1)) else {
            return storageText
        }
        return formatter.string(from: date)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else {
            return 0
        }
        return range.count
    }
}
