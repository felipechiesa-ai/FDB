import CoreGraphics
import FDBDomain
import FDBLibrary
import FDBPersistence
import Foundation
import Observation

/// Shared app state: the open library, a revision counter that tells open screens to reload after a write,
/// and flags that block editing while a restore swaps the library.
@MainActor
@Observable
final class LibraryModel {
    private(set) var store: LibraryStore
    let folder: LibraryFolder
    private(set) var revision = 0
    private(set) var isRestoring = false
    /// Set when a restore could not reopen any library. The app stays blocked until it is relaunched.
    private(set) var isBlocked = false

    init(opened: OpenedLibrary) {
        store = opened.store
        folder = opened.folder
    }

    func didChange() {
        revision += 1
    }

    /// Imports an image off the main thread. The managed copy exists before any record refers to it.
    func importImage(from url: URL) async throws -> MediaAsset {
        let importer = MediaImporter(folder: folder)
        return try await Task.detached(priority: .userInitiated) {
            try importer.importImage(from: url)
        }.value
    }

    /// A cached thumbnail of a stored original. Rendering happens off the main thread.
    func thumbnail(fileName: String, maxPixelSize: Int) async -> CGImage? {
        let thumbnails = MediaThumbnails(folder: folder)
        return await Task.detached(priority: .userInitiated) {
            try? thumbnails.thumbnail(fileName: fileName, maxPixelSize: maxPixelSize)
        }.value
    }

    /// Restores a backup as this library, following the charter: validate and stage a copy beside it, keep a
    /// recovery copy of the current library, close it, swap the folders, reopen, and finish. A failure before the
    /// swap changes nothing. If the restored library will not open, the previous one is put back.
    func restore(from backupURL: URL, recoveryDirectory: URL) async throws -> URL {
        let active = folder
        let placeholder = try LibraryStore(database: LibraryDatabase.openInMemory())
        isRestoring = true
        let staged: StagedRestore
        do {
            staged = try await Task.detached(priority: .userInitiated) { [store] in
                try await LibraryBackup.stageRestore(
                    backupURL,
                    from: store,
                    active: active,
                    recoveryDirectory: recoveryDirectory
                )
            }.value
        } catch {
            isRestoring = false
            throw error
        }

        // Dropping the library's store closes its database, so nothing writes while the folders move.
        store = placeholder
        var swap: RestoreSwap?
        do {
            swap = try await Task.detached(priority: .userInitiated) { try staged.commit() }.value
            store = try await Self.reopen(active)
        } catch {
            do {
                if let swap {
                    try swap.rollback()
                } else {
                    staged.discard()
                }
                store = try await Self.reopen(active)
            } catch {
                isBlocked = true
                throw error
            }
            isRestoring = false
            throw error
        }
        swap?.finish()
        isRestoring = false
        didChange()
        return staged.recoveryBackup
    }

    /// Opens the library file at `folder`, applying any pending migrations, off the main thread.
    private static func reopen(_ folder: LibraryFolder) async throws -> LibraryStore {
        try await Task.detached(priority: .userInitiated) {
            LibraryStore(database: try LibraryDatabase.open(at: folder.databaseURL))
        }.value
    }
}
