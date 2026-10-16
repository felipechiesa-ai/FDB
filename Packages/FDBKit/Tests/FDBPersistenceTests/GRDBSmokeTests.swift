import GRDB
import Testing
@testable import FDBPersistence

@Suite struct GRDBSmokeTests {
    @Test func foreignKeysAreEnforcedOnOpen() throws {
        let queue = try LibraryDatabase.openInMemory()

        let enabled = try queue.read { db in
            try Int.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        #expect(enabled == 1)

        try queue.write { db in
            try db.execute(sql: "CREATE TABLE parent (id INTEGER PRIMARY KEY)")
            try db.execute(sql: "CREATE TABLE child (parent_id INTEGER NOT NULL REFERENCES parent (id))")
        }

        #expect(throws: DatabaseError.self) {
            try queue.write { db in
                try db.execute(sql: "INSERT INTO child (parent_id) VALUES (999)")
            }
        }
    }
}
