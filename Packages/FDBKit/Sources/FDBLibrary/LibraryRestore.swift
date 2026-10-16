import Foundation
import FDBPersistence

/// A restore built in its own folder beside the active library. Until `commit()`, the active library is untouched.
public struct StagedRestore: Sendable {
    public let activeFolder: LibraryFolder
    public let stagingFolder: LibraryFolder
    /// A complete backup of the library this restore replaces. It stays in the recovery folder.
    public let recoveryBackup: URL
    let recoveryDirectory: URL

    /// Moves the active library into the recovery folder and the staged library into its place.
    /// The marker is written first, so the next launch can finish or undo the swap if the app stops midway.
    public func commit() throws -> RestoreSwap {
        let fileManager = FileManager.default
        let replacedURL = recoveryDirectory.appendingPathComponent(uniqueFolderName("Replaced"), isDirectory: true)
        let markerURL = activeFolder.url.deletingLastPathComponent().appendingPathComponent(RestoreMarker.fileName)
        try RestoreMarker(
            activePath: activeFolder.url.path,
            replacedPath: replacedURL.path,
            stagingPath: stagingFolder.url.path
        ).write(to: markerURL)

        do {
            try fileManager.moveItem(at: activeFolder.url, to: replacedURL)
        } catch {
            try? fileManager.removeItem(at: markerURL)
            throw error
        }
        do {
            try fileManager.moveItem(at: stagingFolder.url, to: activeFolder.url)
        } catch {
            // Put the previous library back. Keep the marker if that fails, so the next launch does it.
            if (try? fileManager.moveItem(at: replacedURL, to: activeFolder.url)) != nil {
                try? fileManager.removeItem(at: markerURL)
            }
            throw error
        }
        return RestoreSwap(
            activeFolder: activeFolder,
            replacedFolder: replacedURL,
            recoveryDirectory: recoveryDirectory,
            markerURL: markerURL
        )
    }

    /// Removes the staging library after a failed or cancelled restore. The active library is untouched.
    public func discard() {
        try? FileManager.default.removeItem(at: stagingFolder.url)
    }
}

/// The swap that `StagedRestore.commit()` made. Finish it once the restored library opens; roll it back if it does not.
public struct RestoreSwap: Sendable {
    public let activeFolder: LibraryFolder
    /// The previous library, kept in the recovery folder.
    public let replacedFolder: URL
    let recoveryDirectory: URL
    let markerURL: URL

    /// The restored library opened. Removes the marker. A marker left behind is harmless: the next launch finds
    /// the restored library in place and only removes the marker.
    public func finish() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// The restored library would not open. Moves it into the recovery folder and puts the previous library back.
    public func rollback() throws {
        let fileManager = FileManager.default
        let failedURL = recoveryDirectory.appendingPathComponent(uniqueFolderName("Failed-Restore"), isDirectory: true)
        try fileManager.moveItem(at: activeFolder.url, to: failedURL)
        try fileManager.moveItem(at: replacedFolder, to: activeFolder.url)
        try fileManager.removeItem(at: markerURL)
    }
}

/// Brings the library folders back to a consistent state after a restore was interrupted. Call before the library opens.
public enum LibraryRestoreRecovery {
    public static func recoverIfNeeded(for folder: LibraryFolder) throws {
        let fileManager = FileManager.default
        let markerURL = folder.url.deletingLastPathComponent().appendingPathComponent(RestoreMarker.fileName)
        guard fileManager.fileExists(atPath: markerURL.path) else { return }
        let marker = try JSONCoding.decoder().decode(RestoreMarker.self, from: Data(contentsOf: markerURL))
        guard marker.activePath == folder.url.path else { return }

        if !fileManager.fileExists(atPath: folder.url.path) {
            if fileManager.fileExists(atPath: marker.replacedPath) {
                // The app stopped after the active library moved aside: put it back.
                try fileManager.moveItem(atPath: marker.replacedPath, toPath: marker.activePath)
            } else if fileManager.fileExists(atPath: marker.stagingPath) {
                // The previous library is no longer in the recovery folder: finish with the staged library.
                try fileManager.moveItem(atPath: marker.stagingPath, toPath: marker.activePath)
            }
        }
        // Anything left in the staging folder is a copy of the backup and can go.
        if fileManager.fileExists(atPath: marker.stagingPath) {
            try fileManager.removeItem(atPath: marker.stagingPath)
        }
        try fileManager.removeItem(at: markerURL)
    }
}

/// Written before the first folder move. Records where each folder is, so an interrupted swap can be settled at launch.
struct RestoreMarker: Codable {
    static let fileName = "restore-in-progress.json"

    var activePath: String
    var replacedPath: String
    var stagingPath: String

    func write(to url: URL) throws {
        try JSONCoding.encoder().encode(self).write(to: url, options: .atomic)
    }
}

extension LibraryBackup {
    /// Builds a restore beside the active library: copies the backup into a new folder, checks it against the
    /// manifest, and keeps a recovery backup of the current library. A failure removes the staging folder.
    public static func stageRestore(
        _ backupURL: URL,
        from store: LibraryStore,
        active: LibraryFolder,
        recoveryDirectory: URL,
        now: Date = Date()
    ) async throws -> StagedRestore {
        let manifest = try validate(backupURL)
        let staging = LibraryFolder(url: active.url.deletingLastPathComponent().appendingPathComponent(
            uniqueFolderName("Restoring"),
            isDirectory: true
        ))
        do {
            try copyBackup(backupURL, manifest: manifest, into: staging, now: now)
            try await checkStagedLibrary(staging)
            let recovery = try await create(from: store, folder: active, in: recoveryDirectory, label: "Recovery", now: now)
            return StagedRestore(
                activeFolder: active,
                stagingFolder: staging,
                recoveryBackup: recovery,
                recoveryDirectory: recoveryDirectory
            )
        } catch {
            try? FileManager.default.removeItem(at: staging.url)
            throw error
        }
    }

    private static func copyBackup(_ backupURL: URL, manifest: Manifest, into staging: LibraryFolder, now: Date) throws {
        let fileManager = FileManager.default
        try staging.prepare()
        try fileManager.copyItem(at: backupURL.appendingPathComponent("database.sqlite"), to: staging.databaseURL)
        for name in manifest.mediaFiles {
            try fileManager.copyItem(
                at: backupURL.appendingPathComponent("media/originals/\(name)"),
                to: staging.originalsURL.appendingPathComponent(name)
            )
        }
        try LibraryManifest(
            formatVersion: LibraryManifest.currentFormatVersion,
            libraryID: manifest.libraryID,
            createdAt: now
        ).write(to: staging.manifestURL)
    }

    /// Opens the staged database, which migrates an older snapshot, and checks it against what the manifest promised.
    private static func checkStagedLibrary(_ folder: LibraryFolder) async throws {
        let staged = LibraryStore(database: try LibraryDatabase.open(at: folder.databaseURL))
        for name in try await staged.referencedMediaFileNames() {
            guard FileManager.default.fileExists(atPath: folder.originalsURL.appendingPathComponent(name).path) else {
                throw Failure.missingMedia(name)
            }
        }
        guard try await staged.databaseIsConsistent() else {
            throw Failure.corruptDatabase
        }
    }
}

/// A folder name that is unlikely to exist already: a readable timestamp and a short random suffix.
fileprivate func uniqueFolderName(_ prefix: String) -> String {
    "\(prefix)-\(LibraryBackup.timestamp(Date()))-\(UUID().uuidString.prefix(8))"
}
