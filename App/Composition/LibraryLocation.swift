import Foundation
import FDBPersistence

/// Where FDB keeps its library on this Mac. The sandbox maps this folder into the app's container.
enum LibraryLocation {
    /// Developer flag. It opens a separate fictional library and never touches the personal one.
    static let demoLaunchArgument = "-FDBDemoLibrary"

    static var isDemo: Bool {
        CommandLine.arguments.contains(demoLaunchArgument)
    }

    static func openStore() throws -> LibraryStore {
        let folder = try libraryFolder(demo: isDemo)
        let database = try LibraryDatabase.open(at: folder.appendingPathComponent("database.sqlite"))
        return LibraryStore(database: database)
    }

    private static func libraryFolder(demo: Bool) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "com.pipachiesa.FDB"
        let folder = support
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(demo ? "Demo" : "Library", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
