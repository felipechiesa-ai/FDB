import Foundation

/// A stable identity. The phantom `Tag` keeps player, club, and team IDs from mixing.
public struct EntityID<Tag>: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }
}

public enum PlayerTag {}
public enum ClubTag {}
public enum TeamTag {}
public enum CountryTag {}
public enum MembershipTag {}

public typealias PlayerID = EntityID<PlayerTag>
public typealias ClubID = EntityID<ClubTag>
public typealias TeamID = EntityID<TeamTag>
public typealias CountryID = EntityID<CountryTag>
public typealias MembershipID = EntityID<MembershipTag>
