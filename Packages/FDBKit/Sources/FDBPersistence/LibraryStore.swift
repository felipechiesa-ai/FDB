import Foundation
import GRDB
import FDBDomain

public enum LibraryStoreError: Error, Equatable, Sendable {
    case notFound
    case unreadableValue(column: String)
}

extension LibraryStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound: "That record no longer exists."
        case .unreadableValue: "The library contains a value this version cannot read."
        }
    }
}

/// The only path for reading and writing library facts. Each write runs in one transaction,
/// so a failed save leaves nothing behind.
public final class LibraryStore: Sendable {
    let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func countries() async throws -> [Country] {
        try await database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, iso_code, display_name FROM country ORDER BY display_name")
                .map { row in
                    Country(
                        id: CountryID(rawValue: try LibraryStore.uuid(row, "id")),
                        isoCode: row["iso_code"],
                        displayName: row["display_name"]
                    )
                }
        }
    }
}

extension LibraryStore {
    static func uuid(_ row: Row, _ column: String) throws -> UUID {
        let text: String = row[column]
        guard let uuid = UUID(uuidString: text) else {
            throw LibraryStoreError.unreadableValue(column: column)
        }
        return uuid
    }

    static func optionalDate(_ row: Row, _ column: String) throws -> PartialDate? {
        let text: String? = row[column]
        guard let text else { return nil }
        guard let date = PartialDate(storageText: text) else {
            throw LibraryStoreError.unreadableValue(column: column)
        }
        return date
    }
}

extension String {
    /// Trimmed text, or nil when nothing is left. Storage keeps the user's words, minus stray edges.
    var nonEmptyTrimmed: String? {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
