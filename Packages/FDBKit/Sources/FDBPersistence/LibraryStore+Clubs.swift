import Foundation
import GRDB
import FDBDomain

/// One row in the clubs directory. Full profiles load through `club(id:)`.
public struct ClubListItem: Identifiable, Hashable, Sendable {
    public var id: ClubID
    public var displayName: String
    public var city: String?
    public var countryName: String?
    public var teamCount: Int
    public var isArchived: Bool
}

extension LibraryStore {
    public func clubList(search: String = "", includeArchived: Bool = false) async throws -> [ClubListItem] {
        let query = SearchText.fold(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.id, c.display_name, c.city, co.display_name AS country_name, c.is_archived,
                       (SELECT COUNT(*) FROM team t WHERE t.club_id = c.id AND t.is_archived = 0) AS team_count
                FROM club c
                LEFT JOIN country co ON co.id = c.country_id
                WHERE (? = 1 OR c.is_archived = 0)
                  AND (? = '' OR instr(c.search_key, ?) > 0)
                ORDER BY c.sort_key, c.id
                """, arguments: [includeArchived ? 1 : 0, query, query])
                .map { row in
                    ClubListItem(
                        id: ClubID(rawValue: try LibraryStore.uuid(row, "id")),
                        displayName: row["display_name"],
                        city: row["city"],
                        countryName: row["country_name"],
                        teamCount: row["team_count"],
                        isArchived: (row["is_archived"] as Int) == 1
                    )
                }
        }
    }

    public func club(id: ClubID) async throws -> Club? {
        let key = id.rawValue.uuidString
        return try await database.read { db -> Club? in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM club WHERE id = ?", arguments: [key]) else {
                return nil
            }
            return Club(
                id: id,
                displayName: row["display_name"],
                officialName: row["official_name"],
                shortName: row["short_name"],
                city: row["city"],
                countryID: (row["country_id"] as String?)
                    .flatMap(UUID.init(uuidString:))
                    .map { CountryID(rawValue: $0) },
                foundedDate: try LibraryStore.optionalDate(row, "founded_date"),
                notes: row["notes"],
                isArchived: (row["is_archived"] as Int) == 1,
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        }
    }

    /// Saves a club. A new club also gets one senior team, so it is usable before its teams are organized.
    public func saveClub(_ club: Club, badge: MediaChange = .unchanged) async throws {
        try club.validate()
        let key = club.id.rawValue.uuidString
        let searchKey = SearchText.fold(
            [club.displayName, club.officialName ?? "", club.shortName ?? "", club.city ?? ""].joined(separator: " ")
        )
        let sortKey = SearchText.fold(club.displayName)
        try await database.write { db in
            let isNew = try Bool.fetchOne(db, sql: "SELECT NOT EXISTS (SELECT 1 FROM club WHERE id = ?)", arguments: [key]) ?? true
            let values: [(any DatabaseValueConvertible)?] = [
                key,
                club.displayName.nonEmptyTrimmed ?? "",
                club.officialName?.nonEmptyTrimmed,
                club.shortName?.nonEmptyTrimmed,
                club.city?.nonEmptyTrimmed,
                club.countryID?.rawValue.uuidString,
                club.foundedDate?.storageText,
                club.notes?.nonEmptyTrimmed,
                searchKey,
                sortKey,
                club.isArchived ? 1 : 0,
                club.createdAt,
                Date()
            ]
            try db.execute(sql: """
                INSERT INTO club (id, display_name, official_name, short_name, city, country_id, founded_date,
                                  notes, search_key, sort_key, is_archived, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET
                    display_name = excluded.display_name,
                    official_name = excluded.official_name,
                    short_name = excluded.short_name,
                    city = excluded.city,
                    country_id = excluded.country_id,
                    founded_date = excluded.founded_date,
                    notes = excluded.notes,
                    search_key = excluded.search_key,
                    sort_key = excluded.sort_key,
                    is_archived = excluded.is_archived,
                    updated_at = excluded.updated_at
                """, arguments: StatementArguments(values))

            if isNew {
                try LibraryStore.upsertTeam(
                    Team(clubID: club.id, displayName: "Senior", category: .senior),
                    in: db
                )
            }
            try LibraryStore.applyBadge(badge, clubKey: key, in: db)
        }
    }

    public func setClubArchived(_ id: ClubID, isArchived: Bool) async throws {
        try await database.write { db in
            try db.execute(
                sql: "UPDATE club SET is_archived = ?, updated_at = ? WHERE id = ?",
                arguments: [isArchived ? 1 : 0, Date(), id.rawValue.uuidString]
            )
            guard db.changesCount == 1 else { throw LibraryStoreError.notFound }
        }
    }

    /// Teams of one club: senior first, then reserve, youth, and other, then by name.
    public func teams(clubID: ClubID) async throws -> [Team] {
        let key = clubID.rawValue.uuidString
        return try await database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM team WHERE club_id = ?
                ORDER BY CASE category WHEN 'senior' THEN 0 WHEN 'reserve' THEN 1 WHEN 'youth' THEN 2 ELSE 3 END,
                         display_name, id
                """, arguments: [key])
                .map { row in try LibraryStore.team(from: row) }
        }
    }

    public func team(id: TeamID) async throws -> Team? {
        let key = id.rawValue.uuidString
        return try await database.read { db -> Team? in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM team WHERE id = ?", arguments: [key]) else {
                return nil
            }
            return try LibraryStore.team(from: row)
        }
    }

    public func saveTeam(_ team: Team) async throws {
        try team.validate()
        try await database.write { db in
            try LibraryStore.upsertTeam(team, in: db)
        }
    }

    static func upsertTeam(_ team: Team, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO team (id, club_id, display_name, category, age_group, gender_category,
                              is_archived, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                club_id = excluded.club_id,
                display_name = excluded.display_name,
                category = excluded.category,
                age_group = excluded.age_group,
                gender_category = excluded.gender_category,
                is_archived = excluded.is_archived,
                updated_at = excluded.updated_at
            """, arguments: [
                team.id.rawValue.uuidString,
                team.clubID.rawValue.uuidString,
                team.displayName.nonEmptyTrimmed ?? "",
                team.category.rawValue,
                team.ageGroup?.nonEmptyTrimmed,
                team.genderCategory.rawValue,
                team.isArchived ? 1 : 0,
                team.createdAt,
                Date()
            ])
    }

    static func team(from row: Row) throws -> Team {
        let categoryCode: String = row["category"]
        let genderCode: String = row["gender_category"]
        guard let category = TeamCategory(rawValue: categoryCode) else {
            throw LibraryStoreError.unreadableValue(column: "category")
        }
        guard let gender = GenderCategory(rawValue: genderCode) else {
            throw LibraryStoreError.unreadableValue(column: "gender_category")
        }
        return Team(
            id: TeamID(rawValue: try uuid(row, "id")),
            clubID: ClubID(rawValue: try uuid(row, "club_id")),
            displayName: row["display_name"],
            category: category,
            ageGroup: row["age_group"],
            genderCategory: gender,
            isArchived: (row["is_archived"] as Int) == 1,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }
}
