import CryptoKit
import Foundation
import GRDB
import FDBPersistence

/// Full-library backups. A backup is a folder: a manifest, a consistent database snapshot, and the originals it references.
public enum LibraryBackup {
    public static let formatVersion = 1
    public static let pathExtension = "fdbbackup"

    public struct Manifest: Codable, Sendable, Equatable {
        public var formatVersion: Int
        public var libraryID: UUID
        public var createdAt: Date
        public var migrations: [String]
        public var databaseSHA256: String
        public var mediaFiles: [String]
    }

    public enum Failure: Error, Equatable, Sendable {
        case notABackup
        case newerFormat(Int)
        case corruptDatabase
        case schemaNewerThanApp
        case missingMedia(String)
        case mediaChecksumMismatch(String)
        case destinationExists
    }

    /// Writes a complete backup into `directory`. The backup folder appears only once it is complete.
    public static func create(
        from store: LibraryStore,
        folder: LibraryFolder,
        in directory: URL,
        label: String = "Backup",
        now: Date = Date()
    ) async throws -> URL {
        let fileManager = FileManager.default
        let finalURL = directory.appendingPathComponent(
            "FDB-\(label)-\(timestamp(now)).\(pathExtension)",
            isDirectory: true
        )
        guard !fileManager.fileExists(atPath: finalURL.path) else { throw Failure.destinationExists }

        let partialURL = directory.appendingPathComponent(".\(finalURL.lastPathComponent).partial", isDirectory: true)
        try? fileManager.removeItem(at: partialURL)
        let partialOriginals = partialURL.appendingPathComponent("media/originals", isDirectory: true)
        try fileManager.createDirectory(at: partialOriginals, withIntermediateDirectories: true)

        let databaseURL = partialURL.appendingPathComponent("database.sqlite")
        try await store.backupDatabase(to: databaseURL)
        let mediaFiles = try await store.referencedMediaFileNames()
        for name in mediaFiles {
            let source = folder.originalsURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { throw Failure.missingMedia(name) }
            try fileManager.copyItem(at: source, to: partialOriginals.appendingPathComponent(name))
        }

        let manifest = Manifest(
            formatVersion: formatVersion,
            libraryID: (try? LibraryManifest.read(from: folder.manifestURL))?.libraryID ?? UUID(),
            createdAt: now,
            migrations: try await store.schemaMigrationIdentifiers(),
            databaseSHA256: try sha256(of: databaseURL),
            mediaFiles: mediaFiles
        )
        try JSONCoding.encoder().encode(manifest)
            .write(to: partialURL.appendingPathComponent("manifest.json"), options: .atomic)
        try fileManager.moveItem(at: partialURL, to: finalURL)
        return finalURL
    }

    /// Checks the manifest, the snapshot, its integrity, and every referenced original. Changes nothing.
    @discardableResult
    public static func validate(_ backupURL: URL) throws -> Manifest {
        guard let data = try? Data(contentsOf: backupURL.appendingPathComponent("manifest.json")),
              let manifest = try? JSONCoding.decoder().decode(Manifest.self, from: data) else {
            throw Failure.notABackup
        }
        if manifest.formatVersion > formatVersion {
            throw Failure.newerFormat(manifest.formatVersion)
        }
        guard manifest.formatVersion == formatVersion else { throw Failure.notABackup }

        let databaseURL = backupURL.appendingPathComponent("database.sqlite")
        guard (try? sha256(of: databaseURL)) == manifest.databaseSHA256 else { throw Failure.corruptDatabase }
        try checkDatabase(at: databaseURL)

        for name in manifest.mediaFiles {
            let file = backupURL.appendingPathComponent("media/originals/\(name)")
            guard let bytes = try? Data(contentsOf: file) else { throw Failure.missingMedia(name) }
            let expected = String(name.prefix { $0 != "." })
            guard sha256(bytes) == expected else { throw Failure.mediaChecksumMismatch(name) }
        }
        return manifest
    }

    private static func checkDatabase(at url: URL) throws {
        var configuration = Configuration()
        configuration.readonly = true
        do {
            let queue = try DatabaseQueue(path: url.path, configuration: configuration)
            let checks = try queue.read { db -> (integrity: String?, foreignKeyProblems: Int, applied: [String]) in
                (
                    try String.fetchOne(db, sql: "PRAGMA integrity_check"),
                    try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count,
                    try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
                )
            }
            guard checks.integrity == "ok", checks.foreignKeyProblems == 0 else {
                throw Failure.corruptDatabase
            }
            guard Set(checks.applied).isSubset(of: Set(LibraryDatabase.knownMigrationIdentifiers)) else {
                throw Failure.schemaNewerThanApp
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.corruptDatabase
        }
    }

    static func sha256(of url: URL) throws -> String {
        sha256(try Data(contentsOf: url))
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}

extension LibraryBackup.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notABackup: "That folder is not an FDB backup."
        case .newerFormat(let version): "This backup was made by a newer version of FDB (format \(version))."
        case .corruptDatabase: "The backup's database is damaged, so nothing was restored."
        case .schemaNewerThanApp: "The backup uses a newer library schema than this version of FDB."
        case .missingMedia(let name): "The backup is missing an image file (\(name))."
        case .mediaChecksumMismatch(let name): "An image in the backup does not match its checksum (\(name))."
        case .destinationExists: "A backup with that name already exists."
        }
    }
}
