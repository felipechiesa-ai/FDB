import Foundation
import Testing
import FDBDomain
import FDBPersistence
@testable import FDBLibrary

@Suite struct LibraryBackupTests {
    private struct Library {
        let folder: LibraryFolder
        let store: LibraryStore
    }

    private func makeLibrary() throws -> Library {
        let folder = try makeTestLibraryFolder()
        let store = LibraryStore(database: try LibraryDatabase.open(at: folder.databaseURL))
        return Library(folder: folder, store: store)
    }

    private func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One club with a badge and one player with a portrait.
    private func addProfiles(to library: Library) async throws -> (player: Player, portrait: MediaAsset) {
        let portraitSource = library.folder.url.appendingPathComponent("portrait.png")
        try writeTestImage(to: portraitSource, width: 64, height: 64)
        let portrait = try MediaImporter(folder: library.folder).importImage(from: portraitSource)
        let badgeSource = library.folder.url.appendingPathComponent("badge.png")
        try writeTestImage(to: badgeSource, width: 32, height: 32)
        let badge = try MediaImporter(folder: library.folder).importImage(from: badgeSource)
        try await library.store.saveClub(Club(displayName: "Club Ejemplo"), badge: .set(badge))
        let player = Player(displayName: "Ana Ruiz")
        try await library.store.savePlayer(player, portrait: .set(portrait))
        return (player, portrait)
    }

    @Test func restoreBringsBackTheEarlierRecordsAndImages() async throws {
        let library = try makeLibrary()
        let scratch = try makeScratchDirectory()
        let (player, portrait) = try await addProfiles(to: library)
        let backup = try await LibraryBackup.create(from: library.store, folder: library.folder, in: scratch)

        try await library.store.savePlayer(Player(id: player.id, displayName: "Changed Name"), portrait: .remove)
        try FileManager.default.removeItem(at: library.folder.originalsURL.appendingPathComponent(portrait.fileName))

        let recoveryDirectory = scratch.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let recovery = try await LibraryBackup.restore(
            backup,
            into: library.store,
            folder: library.folder,
            recoveryDirectory: recoveryDirectory
        )

        let restored = try #require(try await library.store.player(id: player.id))
        #expect(restored.displayName == "Ana Ruiz")
        let restoredPortrait = try #require(try await library.store.portrait(for: player.id))
        #expect(restoredPortrait.sha256 == portrait.sha256)
        #expect(FileManager.default.fileExists(atPath: library.folder.originalsURL.appendingPathComponent(portrait.fileName).path))
        try LibraryBackup.validate(recovery)
    }

    @Test func malformedBackupIsRefusedAndTheLibraryStaysAsItWas() async throws {
        let library = try makeLibrary()
        let scratch = try makeScratchDirectory()
        let (player, _) = try await addProfiles(to: library)
        let backup = try await LibraryBackup.create(from: library.store, folder: library.folder, in: scratch)
        try FileManager.default.removeItem(at: backup.appendingPathComponent("manifest.json"))

        let recoveryDirectory = scratch.appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        await #expect(throws: LibraryBackup.Failure.notABackup) {
            try await LibraryBackup.restore(backup, into: library.store, folder: library.folder, recoveryDirectory: recoveryDirectory)
        }
        #expect(try await library.store.player(id: player.id)?.displayName == "Ana Ruiz")
    }

    @Test func newerBackupFormatIsRefused() async throws {
        let library = try makeLibrary()
        let scratch = try makeScratchDirectory()
        _ = try await addProfiles(to: library)
        let backup = try await LibraryBackup.create(from: library.store, folder: library.folder, in: scratch)

        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONCoding.decoder().decode(LibraryBackup.Manifest.self, from: Data(contentsOf: manifestURL))
        manifest.formatVersion = 2
        try JSONCoding.encoder().encode(manifest).write(to: manifestURL)

        #expect(throws: LibraryBackup.Failure.newerFormat(2)) {
            try LibraryBackup.validate(backup)
        }
    }

    @Test func corruptedDatabaseSnapshotIsRefused() async throws {
        let library = try makeLibrary()
        let scratch = try makeScratchDirectory()
        _ = try await addProfiles(to: library)
        let backup = try await LibraryBackup.create(from: library.store, folder: library.folder, in: scratch)

        let databaseURL = backup.appendingPathComponent("database.sqlite")
        var bytes = try Data(contentsOf: databaseURL)
        bytes.append(contentsOf: [0, 1, 2, 3])
        try bytes.write(to: databaseURL)

        #expect(throws: LibraryBackup.Failure.corruptDatabase) {
            try LibraryBackup.validate(backup)
        }
    }

    @Test func freshBackupValidatesAndListsItsOriginals() async throws {
        let library = try makeLibrary()
        let scratch = try makeScratchDirectory()
        let (_, portrait) = try await addProfiles(to: library)

        let backup = try await LibraryBackup.create(from: library.store, folder: library.folder, in: scratch)
        let manifest = try LibraryBackup.validate(backup)

        #expect(manifest.formatVersion == LibraryBackup.formatVersion)
        #expect(manifest.mediaFiles.count == 2)
        #expect(manifest.mediaFiles.contains(portrait.fileName))
        #expect(manifest.migrations == LibraryDatabase.knownMigrationIdentifiers)
    }
}
