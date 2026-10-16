import Foundation

public enum MembershipStatus: String, CaseIterable, Sendable, Codable {
    case current, former, uncertain

    public var label: String {
        switch self {
        case .current: "Current"
        case .former: "Former"
        case .uncertain: "Uncertain"
        }
    }
}

/// A player's dated place in one team. Dates describe the roster, not a contract.
public struct RosterMembership: Identifiable, Hashable, Sendable {
    public var id: MembershipID
    public var playerID: PlayerID
    public var teamID: TeamID
    public var startDate: PartialDate?
    /// The first day no longer on the roster, for exact dates. Partial dates are shown as uncertain.
    public var endDate: PartialDate?
    public var shirtNumber: Int?
    public var status: MembershipStatus
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MembershipID = MembershipID(),
        playerID: PlayerID,
        teamID: TeamID,
        startDate: PartialDate? = nil,
        endDate: PartialDate? = nil,
        shirtNumber: Int? = nil,
        status: MembershipStatus = .current,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.startDate = startDate
        self.endDate = endDate
        self.shirtNumber = shirtNumber
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        if let shirtNumber, !(1...99).contains(shirtNumber) {
            throw DomainError.invalidShirtNumber
        }
        if let startDate, let endDate,
           startDate.precision == .day, endDate.precision == .day,
           startDate.earliestSortKey >= endDate.earliestSortKey {
            throw DomainError.invalidInterval
        }
    }

    /// True when the two date spans intersect. The end is exclusive, so a membership that ends on
    /// the day another starts does not overlap it. A missing bound is open-ended.
    public func overlaps(_ other: RosterMembership) -> Bool {
        let selfStart = startDate?.earliestSortKey ?? Int.min
        let selfEnd = endDate?.earliestSortKey ?? Int.max
        let otherStart = other.startDate?.earliestSortKey ?? Int.min
        let otherEnd = other.endDate?.earliestSortKey ?? Int.max
        return selfStart < otherEnd && otherStart < selfEnd
    }
}
