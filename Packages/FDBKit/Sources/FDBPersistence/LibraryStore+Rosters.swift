import Foundation
import GRDB
import FDBDomain

/// One player in a team's roster.
public struct RosterEntry: Identifiable, Hashable, Sendable {
    public var membership: RosterMembership
    public var playerName: String
    public var playerIsArchived: Bool

    public var id: MembershipID { membership.id }
}

/// One of a player's team memberships, with its team and club names for display.
public struct PlayerMembershipEntry: Identifiable, Hashable, Sendable {
    public var membership: RosterMembership
    public var teamName: String
    public var clubID: ClubID
    public var clubName: String

    public var id: MembershipID { membership.id }
}

extension LibraryStore {
    /// The team's roster in shirt-number order. Players without a number come last.
    public func roster(teamID: TeamID) async throws -> [RosterEntry] {
        let key = teamID.rawValue.uuidString
        return try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id, m.player_id, m.team_id, m.start_date, m.end_date, m.shirt_number, m.status,
                       m.notes, m.created_at, m.updated_at,
                       p.display_name AS player_name, p.is_archived AS player_archived
                FROM roster_membership m
                JOIN player p ON p.id = m.player_id
                WHERE m.team_id = ?
                ORDER BY m.shirt_number IS NULL, m.shirt_number, p.sort_key, m.id
                """, arguments: [key])
                .map { row in
                    RosterEntry(
                        membership: try LibraryStore.membership(from: row),
                        playerName: row["player_name"],
                        playerIsArchived: (row["player_archived"] as Int) == 1
                    )
                }
        }
    }

    /// A player's memberships, newest start first. Unknown starts come last.
    public func memberships(playerID: PlayerID) async throws -> [PlayerMembershipEntry] {
        let key = playerID.rawValue.uuidString
        return try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT m.id, m.player_id, m.team_id, m.start_date, m.end_date, m.shirt_number, m.status,
                       m.notes, m.created_at, m.updated_at,
                       t.display_name AS team_name, c.id AS club_id, c.display_name AS club_name
                FROM roster_membership m
                JOIN team t ON t.id = m.team_id
                JOIN club c ON c.id = t.club_id
                WHERE m.player_id = ?
                ORDER BY m.start_date IS NULL, m.start_date DESC, m.id
                """, arguments: [key])
                .map { row in
                    PlayerMembershipEntry(
                        membership: try LibraryStore.membership(from: row),
                        teamName: row["team_name"],
                        clubID: ClubID(rawValue: try LibraryStore.uuid(row, "club_id")),
                        clubName: row["club_name"]
                    )
                }
        }
    }

    /// Saves a membership after its dates, shirt number, and overlap rules pass.
    public func saveMembership(_ membership: RosterMembership) async throws {
        try membership.validate()
        try await database.write { db in
            try LibraryStore.upsertMembership(membership, in: db)
        }
    }

    /// Removes a player from a team by ending the membership on `endDate`,
    /// the first day no longer on the roster. The player and history stay intact.
    public func endMembership(_ id: MembershipID, on endDate: PartialDate) async throws {
        let key = id.rawValue.uuidString
        try await database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM roster_membership WHERE id = ?", arguments: [key]) else {
                throw LibraryStoreError.notFound
            }
            var membership = try LibraryStore.membership(from: row)
            membership.endDate = endDate
            membership.status = .former
            membership.updatedAt = Date()
            try LibraryStore.upsertMembership(membership, in: db)
        }
    }

    static func upsertMembership(_ membership: RosterMembership, in db: Database) throws {
        try membership.validate()
        let others = try Row.fetchAll(db, sql: """
            SELECT * FROM roster_membership WHERE player_id = ? AND team_id = ? AND id <> ?
            """, arguments: [
                membership.playerID.rawValue.uuidString,
                membership.teamID.rawValue.uuidString,
                membership.id.rawValue.uuidString
            ])
            .map { try LibraryStore.membership(from: $0) }
        if others.contains(where: membership.overlaps) {
            throw DomainError.overlappingMembership
        }
        try db.execute(sql: """
            INSERT INTO roster_membership (id, player_id, team_id, start_date, end_date, shirt_number,
                                           status, notes, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                player_id = excluded.player_id,
                team_id = excluded.team_id,
                start_date = excluded.start_date,
                end_date = excluded.end_date,
                shirt_number = excluded.shirt_number,
                status = excluded.status,
                notes = excluded.notes,
                updated_at = excluded.updated_at
            """, arguments: [
                membership.id.rawValue.uuidString,
                membership.playerID.rawValue.uuidString,
                membership.teamID.rawValue.uuidString,
                membership.startDate?.storageText,
                membership.endDate?.storageText,
                membership.shirtNumber,
                membership.status.rawValue,
                membership.notes?.nonEmptyTrimmed,
                membership.createdAt,
                Date()
            ])
    }

    static func membership(from row: Row) throws -> RosterMembership {
        let statusCode: String = row["status"]
        guard let status = MembershipStatus(rawValue: statusCode) else {
            throw LibraryStoreError.unreadableValue(column: "status")
        }
        return RosterMembership(
            id: MembershipID(rawValue: try uuid(row, "id")),
            playerID: PlayerID(rawValue: try uuid(row, "player_id")),
            teamID: TeamID(rawValue: try uuid(row, "team_id")),
            startDate: try optionalDate(row, "start_date"),
            endDate: try optionalDate(row, "end_date"),
            shirtNumber: row["shirt_number"],
            status: status,
            notes: row["notes"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
