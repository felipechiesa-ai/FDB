import Foundation
import GRDB
import Testing
import FDBDomain
@testable import FDBPersistence

@Suite struct MigrationTests {
    /// A version-one library written by the first release keeps its players after the media migration.
    @Test func versionOneLibraryUpgradesWithoutLosingPlayers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("database.sqlite")
        let playerID = UUID()

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        do {
            let original = try DatabaseQueue(path: url.path, configuration: configuration)
            try LibrarySchema.makeMigrator(upTo: LibrarySchema.v1Identifier).migrate(original)
            try await original.write { db in
                try db.execute(
                    sql: "INSERT INTO player (id, display_name, created_at, updated_at) VALUES (?, ?, ?, ?)",
                    arguments: [playerID.uuidString, "Before Upgrade", Date(), Date()]
                )
            }
        }

        let store = LibraryStore(database: try LibraryDatabase.open(at: url))
        let player = try #require(try await store.player(id: PlayerID(rawValue: playerID)))
        #expect(player.displayName == "Before Upgrade")
        #expect(try await store.portrait(for: player.id) == nil)
        #expect(try await store.schemaMigrationIdentifiers() == LibrarySchema.knownIdentifiers)
    }
}
