import Foundation

public enum PreferredFoot: String, CaseIterable, Sendable, Codable {
    case right, left, both

    public var label: String {
        switch self {
        case .right: "Right"
        case .left: "Left"
        case .both: "Both"
        }
    }
}

/// Controlled position codes. The raw values are the stored codes.
public enum PlayerPosition: String, CaseIterable, Sendable, Codable {
    case gk, cb, lb, rb, dm, cm, am, lw, rw, cf, unspecified

    public var label: String {
        switch self {
        case .gk: "Goalkeeper"
        case .cb: "Center-back"
        case .lb: "Left-back"
        case .rb: "Right-back"
        case .dm: "Defensive midfielder"
        case .cm: "Central midfielder"
        case .am: "Attacking midfielder"
        case .lw: "Left winger"
        case .rw: "Right winger"
        case .cf: "Center forward"
        case .unspecified: "Unspecified"
        }
    }
}

public struct PlayerPositionAssignment: Hashable, Sendable, Codable {
    public var position: PlayerPosition
    public var isPrimary: Bool

    public init(position: PlayerPosition, isPrimary: Bool = false) {
        self.position = position
        self.isPrimary = isPrimary
    }
}

public struct Player: Identifiable, Hashable, Sendable {
    public var id: PlayerID
    public var displayName: String
    public var fullName: String?
    public var aliases: [String]
    public var birthDate: PartialDate?
    public var birthCity: String?
    public var birthCountryID: CountryID?
    public var heightCm: Int?
    public var preferredFoot: PreferredFoot?
    public var citizenshipIDs: [CountryID]
    public var positions: [PlayerPositionAssignment]
    public var notes: String?
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: PlayerID = PlayerID(),
        displayName: String,
        fullName: String? = nil,
        aliases: [String] = [],
        birthDate: PartialDate? = nil,
        birthCity: String? = nil,
        birthCountryID: CountryID? = nil,
        heightCm: Int? = nil,
        preferredFoot: PreferredFoot? = nil,
        citizenshipIDs: [CountryID] = [],
        positions: [PlayerPositionAssignment] = [],
        notes: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.fullName = fullName
        self.aliases = aliases
        self.birthDate = birthDate
        self.birthCity = birthCity
        self.birthCountryID = birthCountryID
        self.heightCm = heightCm
        self.preferredFoot = preferredFoot
        self.citizenshipIDs = citizenshipIDs
        self.positions = positions
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Rules that need no database. References and uniqueness of IDs are enforced in persistence.
    public func validate() throws {
        guard !displayName.trimmed.isEmpty else { throw DomainError.emptyName }
        if let heightCm, !(50...260).contains(heightCm) {
            throw DomainError.invalidHeight
        }
        if positions.filter(\.isPrimary).count > 1 {
            throw DomainError.multiplePrimaryPositions
        }
        if Set(positions.map(\.position)).count != positions.count {
            throw DomainError.duplicatePosition
        }
        if Set(citizenshipIDs).count != citizenshipIDs.count {
            throw DomainError.duplicateCitizenship
        }
    }

    /// Whole years on `date`. Only an exact birth date gives an age.
    public func age(on date: Date, calendar: Calendar = .current) -> Int? {
        guard let birthDate, birthDate.precision == .day,
              let month = birthDate.month, let day = birthDate.day,
              let birth = calendar.date(from: DateComponents(year: birthDate.year, month: month, day: day)) else {
            return nil
        }
        return calendar.dateComponents([.year], from: birth, to: date).year
    }
}
