import GRDB

/// Entry point for opening FDB library databases.
public enum LibraryDatabase {
    /// Opens an in-memory database with the connection settings every FDB library uses.
    public static func openInMemory() throws -> DatabaseQueue {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try DatabaseQueue(configuration: configuration)
    }
}
