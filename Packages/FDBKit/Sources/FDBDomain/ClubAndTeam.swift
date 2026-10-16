import Foundation

public struct Club: Identifiable, Hashable, Sendable {
    public var id: ClubID
    public var displayName: String
    public var officialName: String?
    public var shortName: String?
    public var city: String?
    public var countryID: CountryID?
    public var foundedDate: PartialDate?
    public var notes: String?
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ClubID = ClubID(),
        displayName: String,
        officialName: String? = nil,
        shortName: String? = nil,
        city: String? = nil,
        countryID: CountryID? = nil,
        foundedDate: PartialDate? = nil,
        notes: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.officialName = officialName
        self.shortName = shortName
        self.city = city
        self.countryID = countryID
        self.foundedDate = foundedDate
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !displayName.trimmed.isEmpty else { throw DomainError.emptyName }
    }
}

/// A team's sporting level within its club. Stored as a controlled code, never inferred from its name.
public enum TeamCategory: String, CaseIterable, Sendable, Codable {
    case senior, reserve, youth, other

    public var label: String {
        switch self {
        case .senior: "Senior"
        case .reserve: "Reserve"
        case .youth: "Youth"
        case .other: "Other"
        }
    }
}

public enum GenderCategory: String, CaseIterable, Sendable, Codable {
    case mens, womens, mixed, unspecified

    public var label: String {
        switch self {
        case .mens: "Men's"
        case .womens: "Women's"
        case .mixed: "Mixed"
        case .unspecified: "Unspecified"
        }
    }
}

/// A playing team. A club has one or more teams; the club itself is not a squad.
public struct Team: Identifiable, Hashable, Sendable {
    public var id: TeamID
    public var clubID: ClubID
    public var displayName: String
    public var category: TeamCategory
    public var ageGroup: String?
    public var genderCategory: GenderCategory
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: TeamID = TeamID(),
        clubID: ClubID,
        displayName: String,
        category: TeamCategory,
        ageGroup: String? = nil,
        genderCategory: GenderCategory = .unspecified,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.clubID = clubID
        self.displayName = displayName
        self.category = category
        self.ageGroup = ageGroup
        self.genderCategory = genderCategory
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        guard !displayName.trimmed.isEmpty else { throw DomainError.emptyTeamName }
    }
}
