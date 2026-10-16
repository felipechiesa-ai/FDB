import Foundation
import GRDB
import Testing
import FDBDomain
import FDBPersistence
@testable import FDBLibrary

/// Backups and restores run on real folders inside a temporary sandbox that stands in for Application Support.
@Suite struct LibraryBackupTests {
    private struct Sandbox {
        let bundle: URL

        var active: LibraryFolder {
            LibraryFolder(url: bundle.appendingPathComponent("Library", isDirectory: true))
        }

        var recovery: URL {
            bundle.appendingPathComponent("Recovery", isDirectory: true)
        }

        var scratch: URL {
            bundle.appendingPathComponent("Scratch", isDirectory: true)
        }

        var marker: URL {
            bundle.appendingPathComponent(RestoreMarker.fileName)
        }

        func stagingFolderNames() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: bundle.path).filter { $0.hasPrefix("Restoring-") }
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sandbox = Sandbox(bundle: bundle)
        try sandbox.active.prepare()
        try FileManager.default.createDirectory(at: sandbox.scratch, withIntermediateDirectories: true)
        return sandbox
    }

    private func openStore(_ folder: LibraryFolder) throws -> LibraryStore {
        LibraryStore(database: try LibraryDatabase.open(at: folder.databaseURL))
    }

    /// Saves one club with a badge and one player with a portrait. The source images stay outside the library.
    private func addProfiles(_ store: LibraryStore, in sandbox: Sandbox) async throws -> (player: Player, portrait: MediaAsset) {
        let portraitSource = sandbox.scratch.appendingPathComponent("portrait.png")
        try writeTestImage(to: portraitSource, width: 64, height: 64)
        let portrait = try MediaImporter(folder: sandbox.active).importImage(from: portraitSource)
        let badgeSource = sandbox.scratch.appendingPathComponent("badge.png")
        try writeTestImage(to: badgeSource, width: 32, height: 32)
        let badge = try MediaImporter(folder: sandbox.active).importImage(from: badgeSource)
        try await store.saveClub(Club(displayName: "Club Ejemplo"), badge: .set(badge))
        let player = Player(displayName: "Ana Ruiz")
        try await store.savePlayer(player, portrait: .set(portrait))
        return (player, portrait)
    }

    /// Saves a library, backs it up, then renames the player and drops the portrait reference,
    /// so a restore has something to undo.
    private func backUpAndRename(_ store: LibraryStore, in sandbox: Sandbox) async throws -> (player: Player, portrait: MediaAsset, backup: URL) {
        let (player, portrait) = try await addProfiles(store, in: sandbox)
        let backup = try await LibraryBackup.create(from: store, folder: sandbox.active, in: sandbox.scratch)
        try await store.savePlayer(Player(id: player.id, displayName: "Changed Name"), portrait: .remove)
        return (player, portrait, backup)
    }

    @Test func restoreSwapsInTheBackupAndKeepsTheReplacedLibrary() async throws {
        let sandbox = try makeSandbox()
        var store: LibraryStore? = try openStore(sandbox.active)
        let (player, portrait, backup) = try await backUpAndRename(store!, in: sandbox)
        try FileManager.default.removeItem(at: sandbox.active.originalsURL.appendingPathComponent(portrait.fileName))

        let staged = try await LibraryBackup.stageRestore(backup, from: store!, active: sandbox.active, recoveryDirectory: sandbox.recovery)
        store = nil
        let swap = try staged.commit()
        let reopened = try openStore(sandbox.active)
        swap.finish()

        let restored = try #require(try await reopened.player(id: player.id))
        #expect(restored.displayName == "Ana Ruiz")
        let restoredPortrait = try #require(try await reopened.portrait(for: player.id))
        #expect(restoredPortrait.sha256 == portrait.sha256)
        #expect(FileManager.default.fileExists(atPath: sandbox.active.originalsURL.appendingPathComponent(portrait.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.marker.path))

        let replaced = try openStore(LibraryFolder(url: swap.replacedFolder))
        #expect(try await replaced.player(id: player.id)?.displayName == "Changed Name")
        try LibraryBackup.validate(staged.recoveryBackup)
    }

    @Test func rollbackPutsThePreviousLibraryBackAndKeepsTheFailedCopy() async throws {
        let sandbox = try makeSandbox()
        var store: LibraryStore? = try openStore(sandbox.active)
        let (player, _, backup) = try await backUpAndRename(store!, in: sandbox)

        let staged = try await LibraryBackup.stageRestore(backup, from: store!, active: sandbox.active, recoveryDirectory: sandbox.recovery)
        store = nil
        let swap = try staged.commit()
        try swap.rollback()

        let previous = try openStore(sandbox.active)
        #expect(try await previous.player(id: player.id)?.displayName == "Changed Name")
        #expect(!FileManager.default.fileExists(atPath: sandbox.marker.path))
        let failed = try FileManager.default.contentsOfDirectory(atPath: sandbox.recovery.path)
            .filter { $0.hasPrefix("Failed-Restore-") }
        #expect(failed.count == 1)
    }

    @Test func interruptedSwapIsUndoneAtLaunch() async throws {
        let sandbox = try makeSandbox()
        var store: LibraryStore? = try openStore(sandbox.active)
        let (player, _, backup) = try await backUpAndRename(store!, in: sandbox)

        let staged = try await LibraryBackup.stageRestore(backup, from: store!, active: sandbox.active, recoveryDirectory: sandbox.recovery)
        store = nil
        _ = try staged.commit()
        // The app stopped after the active library moved aside and before the staged library moved in.
        try FileManager.default.moveItem(at: sandbox.active.url, to: staged.stagingFolder.url)

        try LibraryRestoreRecovery.recoverIfNeeded(for: sandbox.active)

        let reopened = try openStore(sandbox.active)
        #expect(try await reopened.player(id: player.id)?.displayName == "Changed Name")
        #expect(!FileManager.default.fileExists(atPath: staged.stagingFolder.url.path))
        #expect(!FileManager.default.fileExists(atPath: sandbox.marker.path))
    }

    @Test func interruptedSwapWithoutItsRecoveryCopyFinishesWithTheStagedLibrary() async throws {
        let sandbox = try makeSandbox()
        var store: LibraryStore? = try openStore(sandbox.active)
        let (player, _, backup) = try await backUpAndRename(store!, in: sandbox)

        let staged = try await LibraryBackup.stageRestore(backup, from: store!, active: sandbox.active, recoveryDirectory: sandbox.recovery)
        store = nil
        let swap = try staged.commit()
        // The app stopped before the staged library moved in, and the previous library's recovery folder is gone.
        try FileManager.default.moveItem(at: sandbox.active.url, to: staged.stagingFolder.url)
        try FileManager.default.removeItem(at: swap.replacedFolder)

        try LibraryRestoreRecovery.recoverIfNeeded(for: sandbox.active)

        let reopened = try openStore(sandbox.active)
        #expect(try await reopened.player(id: player.id)?.displayName == "Ana Ruiz")
        #expect(!FileManager.default.fileExists(atPath: sandbox.marker.path))
    }

    @Test func unfinishedSwapKeepsTheRestoredLibraryAtLaunch() async throws {
        let sandbox = try makeSandbox()
        var store: LibraryStore? = try openStore(sandbox.active)
        let (player, _, backup) = try await backUpAndRename(store!, in: sandbox)

        let staged = try await LibraryBackup.stageRestore(backup, from: store!, active: sandbox.active, recoveryDirectory: sandbox.recovery)
        store = nil
        _ = try staged.commit()
        // The app stopped after both folders moved, before the restore was finished.
        try LibraryRestoreRecovery.recoverIfNeeded(for: sandbox.active)

        let reopened = try openStore(sandbox.active)
        #expect(try await reopened.player(id: player.id)?.displayName == "Ana Ruiz")
        #expect(!FileManager.default.fileExists(atPath: sandbox.marker.path))
    }

    @Test func failedStagingRemovesItsFolderAndLeavesTheLibraryUsable() async throws {
        let sandbox = try makeSandbox()
        let store = try openStore(sandbox.active)
        let (player, _) = try await addProfiles(store, in: sandbox)
        let names = try await store.referencedMediaFileNames()
        let backup = try await LibraryBackup.create(from: store, folder: sandbox.active, in: sandbox.scratch)

        // The manifest forgets the images, so the backup passes validation, but the staged copy cannot show them.
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONCoding.decoder().decode(LibraryBackup.Manifest.self, from: Data(contentsOf: manifestURL))
        manifest.mediaFiles = []
        try JSONCoding.encoder().encode(manifest).write(to: manifestURL)

        await #expect(throws: LibraryBackup.Failure.missingMedia(names[0])) {
            try await LibraryBackup.stageRestore(backup, from: store, active: sandbox.active, recoveryDirectory: sandbox.recovery)
        }
        #expect(try await store.player(id: player.id)?.displayName == "Ana Ruiz")
        #expect(try sandbox.stagingFolderNames().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sandbox.recovery.path))
    }

    @Test func newerBackupFormatIsRefused() async throws {
        let sandbox = try makeSandbox()
        let store = try openStore(sandbox.active)
        _ = try await addProfiles(store, in: sandbox)
        let backup = try await LibraryBackup.create(from: store, folder: sandbox.active, in: sandbox.scratch)

        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONCoding.decoder().decode(LibraryBackup.Manifest.self, from: Data(contentsOf: manifestURL))
        manifest.formatVersion = 2
        try JSONCoding.encoder().encode(manifest).write(to: manifestURL)

        #expect(throws: LibraryBackup.Failure.newerFormat(2)) {
            try LibraryBackup.validate(backup)
        }
    }

    @Test func tamperedDatabaseSnapshotIsRefused() async throws {
        let sandbox = try makeSandbox()
        let store = try openStore(sandbox.active)
        _ = try await addProfiles(store, in: sandbox)
        let backup = try await LibraryBackup.create(from: store, folder: sandbox.active, in: sandbox.scratch)

        let databaseURL = backup.appendingPathComponent("database.sqlite")
        var bytes = try Data(contentsOf: databaseURL)
        bytes.append(contentsOf: [0, 1, 2, 3])
        try bytes.write(to: databaseURL)

        #expect(throws: LibraryBackup.Failure.corruptDatabase) {
            try LibraryBackup.validate(backup)
        }
    }

    @Test func backupWithBrokenRelationshipIsRefused() async throws {
        let sandbox = try makeSandbox()
        let store = try openStore(sandbox.active)
        _ = try await addProfiles(store, in: sandbox)
        let backup = try await LibraryBackup.create(from: store, folder: sandbox.active, in: sandbox.scratch)

        // Point the portrait at an image the library does not have. Foreign keys are off only for this edit, and the
        // manifest is re-signed afterwards, so the relationship check alone must refuse the backup.
        let databaseURL = backup.appendingPathComponent("database.sqlite")
        var configuration = Configuration()
        configuration.foreignKeysEnabled = false
        do {
            let damaged = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try await damaged.write { db in
                try db.execute(sql: "UPDATE player_portrait SET asset_id = ?", arguments: [UUID().uuidString])
            }
        }
        let manifestURL = backup.appendingPathComponent("manifest.json")
        var manifest = try JSONCoding.decoder().decode(LibraryBackup.Manifest.self, from: Data(contentsOf: manifestURL))
        manifest.databaseSHA256 = try LibraryBackup.sha256(of: databaseURL)
        try JSONCoding.encoder().encode(manifest).write(to: manifestURL)

        #expect(throws: LibraryBackup.Failure.corruptDatabase) {
            try LibraryBackup.validate(backup)
        }
    }

    @Test func freshBackupValidatesAndListsItsOriginals() async throws {
        let sandbox = try makeSandbox()
        let store = try openStore(sandbox.active)
        let (_, portrait) = try await addProfiles(store, in: sandbox)

        let backup = try await LibraryBackup.create(from: store, folder: sandbox.active, in: sandbox.scratch)
        let manifest = try LibraryBackup.validate(backup)

        #expect(manifest.formatVersion == LibraryBackup.formatVersion)
        #expect(manifest.mediaFiles.count == 2)
        #expect(manifest.mediaFiles.contains(portrait.fileName))
        #expect(manifest.migrations == LibraryDatabase.knownMigrationIdentifiers)
    }
}
