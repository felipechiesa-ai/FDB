import Foundation
import FDBDomain

enum MembershipFormat {
    /// One line for a membership: shirt number, status, and dates. The end date is the first day off the roster.
    static func summary(_ membership: RosterMembership) -> String {
        var parts: [String] = []
        if let shirt = membership.shirtNumber {
            parts.append("No. \(shirt)")
        }
        parts.append(membership.status.label)
        if let start = membership.startDate {
            parts.append("from \(start.formatted())")
        }
        if let end = membership.endDate {
            parts.append("left on \(end.formatted())")
        }
        return parts.joined(separator: " · ")
    }

    /// A shirt number from form text. Blank means none. Text that is not a whole number is refused;
    /// the range check happens when the membership is validated.
    static func shirtNumber(from text: String) throws -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let number = Int(trimmed) else { throw DomainError.invalidShirtNumber }
        return number
    }
}
