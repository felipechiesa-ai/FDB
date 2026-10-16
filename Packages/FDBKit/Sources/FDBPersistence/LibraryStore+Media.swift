import Foundation
import GRDB
import FDBDomain

/// How a save changes a profile image. `unchanged` keeps the stored reference, so a cancelled edit changes nothing.
public enum MediaChange: Sendable, Equatable {
    case unchanged
    case set(MediaAsset)
    case remove
}

extension LibraryStore {
    public func portrait(for playerID: PlayerID) async throws -> MediaAsset? {
        try await mediaAsset(sql: """
            SELECT a.sha256, a.file_extension, a.mime_type, a.pixel_width, a.pixel_height, a.byte_size, a.created_at
            FROM player_portrait p JOIN media_asset a ON a.id = p.asset_id
            WHERE p.player_id = ?
            """, key: playerID.rawValue.uuidString)
    }

    public func badge(for clubID: ClubID) async throws -> MediaAsset? {
        try await mediaAsset(sql: """
            SELECT a.sha256, a.file_extension, a.mime_type, a.pixel_width, a.pixel_height, a.byte_size, a.created_at
            FROM club_badge b JOIN media_asset a ON a.id = b.asset_id
            WHERE b.club_id = ?
            """, key: clubID.rawValue.uuidString)
    }

    /// File names of every original that a profile image references. Backups copy exactly these.
    public func referencedMediaFileNames() async throws -> [String] {
        try await database.read { db in
            try String.fetchAll(db, sql: """
                SELECT a.sha256 || '.' || a.file_extension FROM media_asset a
                WHERE a.id IN (SELECT asset_id FROM player_portrait UNION SELECT asset_id FROM club_badge)
                ORDER BY 1
                """)
        }
    }

    /// Writes a consistent snapshot of the library database to `url` with SQLite's online backup API.
    public func backupDatabase(to url: URL) async throws {
        let destination = try DatabaseQueue(path: url.path)
        try database.backup(to: destination)
    }

    /// Migrations already applied to this library, in order.
    public func schemaMigrationIdentifiers() async throws -> [String] {
        try await database.read { db in
            guard try db.tableExists("grdb_migrations") else { return [] }
            return try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
    }

    static func applyPortrait(_ change: MediaChange, playerKey: String, in db: Database) throws {
        switch change {
        case .unchanged:
            return
        case .remove:
            try db.execute(sql: "DELETE FROM player_portrait WHERE player_id = ?", arguments: [playerKey])
        case .set(let asset):
            try insertAsset(asset, in: db)
            try db.execute(sql: """
                INSERT INTO player_portrait (player_id, asset_id) VALUES (?, ?)
                ON CONFLICT (player_id) DO UPDATE SET asset_id = excluded.asset_id
                """, arguments: [playerKey, asset.id.rawValue.uuidString])
        }
    }

    static func applyBadge(_ change: MediaChange, clubKey: String, in db: Database) throws {
        switch change {
        case .unchanged:
            return
        case .remove:
            try db.execute(sql: "DELETE FROM club_badge WHERE club_id = ?", arguments: [clubKey])
        case .set(let asset):
            try insertAsset(asset, in: db)
            try db.execute(sql: """
                INSERT INTO club_badge (club_id, asset_id) VALUES (?, ?)
                ON CONFLICT (club_id) DO UPDATE SET asset_id = excluded.asset_id
                """, arguments: [clubKey, asset.id.rawValue.uuidString])
        }
    }

    /// Storing the same image twice is harmless: the row is keyed by content.
    static func insertAsset(_ asset: MediaAsset, in db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO media_asset
                (id, sha256, file_extension, mime_type, pixel_width, pixel_height, byte_size, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                asset.id.rawValue.uuidString,
                asset.sha256,
                asset.fileExtension,
                asset.mimeType,
                asset.pixelWidth,
                asset.pixelHeight,
                asset.byteSize,
                asset.createdAt
            ])
    }

    static func mediaAsset(from row: Row) throws -> MediaAsset {
        MediaAsset(
            sha256: row["sha256"],
            fileExtension: row["file_extension"],
            mimeType: row["mime_type"],
            pixelWidth: row["pixel_width"],
            pixelHeight: row["pixel_height"],
            byteSize: row["byte_size"],
            createdAt: row["created_at"]
        )
    }

    private func mediaAsset(sql: String, key: String) async throws -> MediaAsset? {
        try await database.read { db in
            try Row.fetchOne(db, sql: sql, arguments: [key]).map { try LibraryStore.mediaAsset(from: $0) }
        }
    }
}

extension LibraryStore {
    /// SQLite's integrity check and foreign-key check, run on the open library.
    public func databaseIsConsistent() async throws -> Bool {
        try await database.read { db in
            let integrity = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            let foreignKeyProblems = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count
            return integrity == "ok" && foreignKeyProblems == 0
        }
    }
}
