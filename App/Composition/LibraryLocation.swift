import Foundation
import FDBLibrary
import FDBPersistence

/// The library the app opened: its folder on disk and the store that reads and writes it.
struct OpenedLibrary {
    let folder: LibraryFolder
    let store: LibraryStore
}

/// Where FDB keeps its libraries on this Mac. The sandbox maps these folders into the app's container.
enum LibraryLocation {
    /// Developer flag. It opens a separate fictional library and never touches the personal one.
    static let demoLaunchArgument = "-FDBDemoLibrary"

    static var isDemo: Bool {
        CommandLine.arguments.contains(demoLaunchArgument)
    }

    static func open() throws -> OpenedLibrary {
        let folder = LibraryFolder(url: try libraryFolder(demo: isDemo))
        try folder.prepare()
        let database = try LibraryDatabase.open(at: folder.databaseURL)
        return OpenedLibrary(folder: folder, store: LibraryStore(database: database))
    }

    /// Where a restore keeps the copy of the library it replaces.
    static func recoveryDirectory() throws -> URL {
        let url = try bundleSupportFolder().appendingPathComponent("Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func libraryFolder(demo: Bool) throws -> URL {
        try bundleSupportFolder().appendingPathComponent(demo ? "Demo" : "Library", isDirectory: true)
    }

    private static func bundleSupportFolder() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "com.pipachiesa.FDB"
        return support.appendingPathComponent(bundleID, isDirectory: true)
    }
}
