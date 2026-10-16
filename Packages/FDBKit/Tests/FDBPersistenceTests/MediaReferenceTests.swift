import Foundation
import Testing
import FDBDomain
@testable import FDBPersistence

@Suite struct MediaReferenceTests {
    private func makeStore() throws -> LibraryStore {
        LibraryStore(database: try LibraryDatabase.openInMemory())
    }

    /// A stand-in asset: only the stored metadata matters to the database, not the file.
    private func asset(_ digit: Character) -> MediaAsset {
        MediaAsset(
            sha256: String(repeating: digit, count: 64),
            fileExtension: "png",
            mimeType: "image/png",
            pixelWidth: 10,
            pixelHeight: 10,
            byteSize: 100
        )
    }

    @Test func unchangedPortraitSurvivesOrdinarySaves() async throws {
        let store = try makeStore()
        let player = Player(displayName: "Ana Ruiz")
        try await store.savePlayer(player, portrait: .set(asset("a")))

        try await store.savePlayer(Player(id: player.id, displayName: "Ana R."))

        #expect(try await store.portrait(for: player.id)?.sha256 == String(repeating: "a", count: 64))
    }

    @Test func portraitCanBeSetReplacedAndRemoved() async throws {
        let store = try makeStore()
        let player = Player(displayName: "Ana Ruiz")
        try await store.savePlayer(player, portrait: .set(asset("a")))

        try await store.savePlayer(player, portrait: .set(asset("b")))
        #expect(try await store.portrait(for: player.id)?.sha256 == String(repeating: "b", count: 64))

        try await store.savePlayer(player, portrait: .remove)
        #expect(try await store.portrait(for: player.id) == nil)
    }

    @Test func clubBadgeIsStoredAndListedForBackups() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club, badge: .set(asset("c")))

        #expect(try await store.badge(for: club.id)?.sha256 == String(repeating: "c", count: 64))
        #expect(try await store.referencedMediaFileNames() == [asset("c").fileName])
    }
}
