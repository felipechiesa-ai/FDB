import CoreGraphics
import FDBDomain
import FDBLibrary
import FDBPersistence
import Foundation
import Observation

/// Shared app state: the open library, and a revision counter that tells open screens to reload after a write.
@MainActor
@Observable
final class LibraryModel {
    let store: LibraryStore
    let folder: LibraryFolder
    private(set) var revision = 0

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
}
