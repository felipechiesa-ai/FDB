import Foundation
import GRDB

/// Opens library databases with FDB's connection settings and migrations applied.
public enum LibraryDatabase {
    /// Opens the library file at `url`, creating it and applying migrations when needed.
    public static func open(at url: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path, configuration: configuration())
        try LibrarySchema.migrator.migrate(queue)
        return queue
    }

    /// Identifiers of every migration this build knows. A library with others was written by a newer build.
    public static var knownMigrationIdentifiers: [String] {
        LibrarySchema.knownIdentifiers
    }

    /// Opens an empty in-memory library. Used by tests.
    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: configuration())
        try LibrarySchema.migrator.migrate(queue)
        return queue
    }

    private static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return configuration
    }
}
