import Foundation
import Testing
import FDBDomain
@testable import FDBPersistence

/// Stage 1 budgets on a synthetic library of 10,000 players and 500 clubs. The suite runs only with
/// `FDB_PERFORMANCE=1`, because seeding takes a while. Timings are printed and recorded in docs/verification/01-09.md.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FDB_PERFORMANCE"] == "1"))
struct LibraryPerformanceTests {
    private static let playerCount = 10_000
    private static let clubCount = 500
    private static let directoryBudgetMs = 200.0
    private static let saveBudgetMs = 500.0
    private static let runs = 5
    private static let saveRuns = 20

    private static let givenNames = ["Mateo", "Lucas", "Tomás", "Joaquín", "Nicolás", "Santiago", "Facundo", "Agustín", "Bruno", "Ignacio"]
    private static let familyNames = ["Ruiz", "Gómez", "Pérez", "García", "Díaz", "Fernández", "López", "Martínez", "Sánchez", "Ferrer"]

    @Test func directoriesAndSavesStayWithinTheStageOneBudgets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("database.sqlite")

        // Players share one transaction while seeding. Timing starts after seeding, so this does not affect the budgets.
        let players = (0..<Self.playerCount).map(Self.syntheticPlayer)
        let seeded = LibraryStore(database: try LibraryDatabase.open(at: url))
        let seedMs = try await milliseconds {
            for index in 0..<Self.clubCount {
                try await seeded.saveClub(Club(displayName: "Club \(index)"))
            }
            try await seeded.database.write { db in
                for player in players {
                    try LibraryStore.upsertPlayer(player, portrait: .unchanged, in: db)
                }
            }
        }
        print("FDB performance: seeded \(Self.playerCount) players and \(Self.clubCount) clubs in \(Self.format(seedMs)) ms (not a budget)")

        // A reopened connection makes the first query cold: the store has not run anything on it yet.
        let store = LibraryStore(database: try LibraryDatabase.open(at: url))
        let coldPlayers = try await milliseconds { try await store.playerList() }
        var warmPlayers: [Double] = []
        for _ in 0..<Self.runs {
            warmPlayers.append(try await milliseconds { try await store.playerList() })
        }
        var warmSearch: [Double] = []
        for _ in 0..<Self.runs {
            warmSearch.append(try await milliseconds { try await store.playerList(search: "garcia") })
        }
        var warmClubs: [Double] = []
        for _ in 0..<Self.runs {
            warmClubs.append(try await milliseconds { try await store.clubList() })
        }

        let existing = players[0]
        var saves: [Double] = []
        for run in 0..<Self.saveRuns {
            var edited = existing
            edited.displayName = "Renamed \(run) \(existing.displayName)"
            saves.append(try await milliseconds { try await store.savePlayer(edited) })
        }

        print("""
        FDB performance, \(Self.playerCount) players and \(Self.clubCount) clubs (budget \(Self.format(Self.directoryBudgetMs)) ms for directories, \(Self.format(Self.saveBudgetMs)) ms for saves):
          players, first query after reopening: \(Self.format(coldPlayers)) ms
          players, warm median of \(Self.runs): \(Self.format(Self.median(warmPlayers))) ms
          players, search "garcia" warm median: \(Self.format(Self.median(warmSearch))) ms
          clubs, warm median of \(Self.runs): \(Self.format(Self.median(warmClubs))) ms
          save player, median of \(Self.saveRuns): \(Self.format(Self.median(saves))) ms
        """)

        #expect(coldPlayers <= Self.directoryBudgetMs)
        #expect(Self.median(warmPlayers) <= Self.directoryBudgetMs)
        #expect(Self.median(warmSearch) <= Self.directoryBudgetMs)
        #expect(Self.median(warmClubs) <= Self.directoryBudgetMs)
        #expect(Self.median(saves) <= Self.saveBudgetMs)
    }

    /// Names repeat across the library on purpose, so same-name players are part of the workload.
    private static func syntheticPlayer(_ index: Int) -> Player {
        let given = givenNames[index % givenNames.count]
        let family = familyNames[(index / givenNames.count) % familyNames.count]
        let position = PlayerPosition.allCases[index % PlayerPosition.allCases.count]
        return Player(
            displayName: "\(given) \(family)",
            positions: [PlayerPositionAssignment(position: position, isPrimary: true)]
        )
    }

    /// Wall-clock milliseconds for one call. The result is discarded; only the duration is kept.
    private func milliseconds<T>(_ body: () async throws -> T) async throws -> Double {
        let start = ContinuousClock.now
        _ = try await body()
        let elapsed = start.duration(to: ContinuousClock.now)
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}
