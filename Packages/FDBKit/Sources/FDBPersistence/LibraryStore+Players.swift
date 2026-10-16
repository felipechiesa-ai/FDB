import Foundation
import GRDB
import FDBDomain

/// One row in the players directory. Full profiles load through `player(id:)`.
public struct PlayerListItem: Identifiable, Hashable, Sendable {
    public var id: PlayerID
    public var displayName: String
    public var birthDate: PartialDate?
    public var primaryPosition: PlayerPosition?
    public var isArchived: Bool
}

extension LibraryStore {
    /// Players matching `search` (accent- and case-insensitive), sorted by name then ID.
    public func playerList(search: String = "", position: PlayerPosition? = nil, includeArchived: Bool = false) async throws -> [PlayerListItem] {
        let query = SearchText.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        let positionCode = position?.rawValue
        return try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT p.id, p.display_name, p.birth_date, p.is_archived,
                       (SELECT pp.position_code FROM player_position pp
                         WHERE pp.player_id = p.id AND pp.is_primary = 1) AS primary_position
                FROM player p
                WHERE (? = 1 OR p.is_archived = 0)
                  AND (? = '' OR instr(p.search_key, ?) > 0)
                  AND (? IS NULL OR EXISTS (SELECT 1 FROM player_position f
                        WHERE f.player_id = p.id AND f.position_code = ?))
                ORDER BY p.sort_key, p.id
                """, arguments: [includeArchived ? 1 : 0, query, query, positionCode, positionCode])
                .map { row in
                    PlayerListItem(
                        id: PlayerID(rawValue: try LibraryStore.uuid(row, "id")),
                        displayName: row["display_name"],
                        birthDate: try LibraryStore.optionalDate(row, "birth_date"),
                        primaryPosition: (row["primary_position"] as String?).flatMap(PlayerPosition.init(rawValue:)),
                        isArchived: (row["is_archived"] as Int) == 1
                    )
                }
        }
    }

    public func player(id: PlayerID) async throws -> Player? {
        let key = id.rawValue.uuidString
        return try await database.read { db -> Player? in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM player WHERE id = ?", arguments: [key]) else {
                return nil
            }
            let aliases = try String.fetchAll(
                db,
                sql: "SELECT alias FROM player_alias WHERE player_id = ? ORDER BY alias",
                arguments: [key]
            )
            let citizenshipIDs = try String.fetchAll(db, sql: """
                SELECT pc.country_id FROM player_citizenship pc
                JOIN country c ON c.id = pc.country_id
                WHERE pc.player_id = ? ORDER BY c.display_name
                """, arguments: [key])
                .compactMap { UUID(uuidString: $0) }
                .map { CountryID(rawValue: $0) }
            let positions = try Row.fetchAll(
                db,
                sql: "SELECT position_code, is_primary FROM player_position WHERE player_id = ? ORDER BY position_code",
                arguments: [key]
            )
            .map { positionRow -> PlayerPositionAssignment in
                let code: String = positionRow["position_code"]
                guard let position = PlayerPosition(rawValue: code) else {
                    throw LibraryStoreError.unreadableValue(column: "position_code")
                }
                return PlayerPositionAssignment(position: position, isPrimary: (positionRow["is_primary"] as Int) == 1)
            }
            return Player(
                id: id,
                displayName: row["display_name"],
                fullName: row["full_name"],
                aliases: aliases,
                birthDate: try LibraryStore.optionalDate(row, "birth_date"),
                birthCity: row["birth_city"],
                birthCountryID: (row["birth_country_id"] as String?)
                    .flatMap(UUID.init(uuidString:))
                    .map { CountryID(rawValue: $0) },
                heightCm: row["height_cm"],
                preferredFoot: (row["preferred_foot"] as String?).flatMap(PreferredFoot.init(rawValue:)),
                citizenshipIDs: citizenshipIDs,
                positions: positions,
                notes: row["notes"],
                isArchived: (row["is_archived"] as Int) == 1,
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    /// Validates and saves a player with its aliases, citizenships, and positions in one transaction.
    /// Same-name players stay separate: identity is the ID, never the name.
    public func savePlayer(_ player: Player) async throws {
        try player.validate()
        let key = player.id.rawValue.uuidString
        let aliases = LibraryStore.cleanedAliases(player.aliases)
        let searchKey = SearchText.fold(([player.displayName, player.fullName ?? ""] + aliases).joined(separator: " "))
        let sortKey = SearchText.fold(player.displayName)
        try await database.write { db in
            let values: [(any DatabaseValueConvertible)?] = [
                key,
                player.displayName.nonEmptyTrimmed ?? "",
                player.fullName?.nonEmptyTrimmed,
                player.birthDate?.storageText,
                player.birthCity?.nonEmptyTrimmed,
                player.birthCountryID?.rawValue.uuidString,
                player.heightCm,
                player.preferredFoot?.rawValue,
                player.notes?.nonEmptyTrimmed,
                searchKey,
                sortKey,
                player.isArchived ? 1 : 0,
                player.createdAt,
                Date()
            ]
            try db.execute(sql: """
                INSERT INTO player (id, display_name, full_name, birth_date, birth_city, birth_country_id,
                                    height_cm, preferred_foot, notes, search_key, sort_key, is_archived,
                                    created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    display_name = excluded.display_name,
                    full_name = excluded.full_name,
                    birth_date = excluded.birth_date,
                    birth_city = excluded.birth_city,
                    birth_country_id = excluded.birth_country_id,
                    height_cm = excluded.height_cm,
                    preferred_foot = excluded.preferred_foot,
                    notes = excluded.notes,
                    search_key = excluded.search_key,
                    sort_key = excluded.sort_key,
                    is_archived = excluded.is_archived,
                    updated_at = excluded.updated_at
                """, arguments: StatementArguments(values))

            try db.execute(sql: "DELETE FROM player_alias WHERE player_id = ?", arguments: [key])
            for alias in aliases {
                try db.execute(sql: "INSERT INTO player_alias (player_id, alias) VALUES (?, ?)", arguments: [key, alias])
            }
            try db.execute(sql: "DELETE FROM player_citizenship WHERE player_id = ?", arguments: [key])
            for countryID in player.citizenshipIDs {
                try db.execute(
                    sql: "INSERT INTO player_citizenship (player_id, country_id) VALUES (?, ?)",
                    arguments: [key, countryID.rawValue.uuidString]
                )
            }
            try db.execute(sql: "DELETE FROM player_position WHERE player_id = ?", arguments: [key])
            for assignment in player.positions {
                try db.execute(
                    sql: "INSERT INTO player_position (player_id, position_code, is_primary) VALUES (?, ?, ?)",
                    arguments: [key, assignment.position.rawValue, assignment.isPrimary ? 1 : 0]
                )
            }
        }
    }

    public func setPlayerArchived(_ id: PlayerID, isArchived: Bool) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE player SET is_archived = ?, updated_at = ? WHERE id = ?",
                arguments: [isArchived ? 1 : 0, Date(), id.rawValue.uuidString]
            )
            guard db.changesCount == 1 else { throw LibraryStoreError.notFound }
        }
    }

    /// Trims, drops blanks, and removes case- and accent-insensitive duplicates, keeping the first spelling.
    static func cleanedAliases(_ aliases: [String]) -> [String] {
        var seen = Set<String>()
        return aliases.compactMap { alias in
            guard let cleaned = alias.nonEmptyTrimmed, seen.insert(SearchText.fold(cleaned)).inserted else {
                return nil
            }
            return cleaned
        }
    }
}
