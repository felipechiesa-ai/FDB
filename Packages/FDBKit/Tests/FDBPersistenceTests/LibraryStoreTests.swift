import Foundation
import GRDB
import Testing
import FDBDomain
@testable import FDBPersistence

@Suite struct LibraryStoreTests {
    private func makeStore() throws -> LibraryStore {
        LibraryStore(database: try LibraryDatabase.openInMemory())
    }

    @Test func seedsEveryIsoCountryOnce() async throws {
        let countries = try await makeStore().countries()
        #expect(countries.count == 249)
        #expect(Set(countries.map(\.isoCode)).count == countries.count)
    }

    @Test func countryIdsAreStableAcrossLibraries() async throws {
        let first = try await makeStore().countries().first { $0.isoCode == "AR" }
        let second = try await makeStore().countries().first { $0.isoCode == "AR" }
        #expect(first?.id == second?.id)
    }

    @Test func savesAndReloadsAFullProfile() async throws {
        let store = try makeStore()
        let countries = try await store.countries()
        let argentina = try #require(countries.first { $0.isoCode == "AR" })
        let italy = try #require(countries.first { $0.isoCode == "IT" })
        let player = Player(
            displayName: "Juan Núñez",
            fullName: "Juan Ignacio Núñez",
            aliases: ["Nuñez", "JIN", "nunez"],
            birthDate: PartialDate(year: 1999, month: 3),
            birthCity: "Rosario",
            birthCountryID: argentina.id,
            heightCm: 181,
            preferredFoot: .left,
            citizenshipIDs: [argentina.id, italy.id],
            positions: [
                PlayerPositionAssignment(position: .cb, isPrimary: true),
                PlayerPositionAssignment(position: .cm)
            ],
            notes: "Test profile"
        )
        try await store.savePlayer(player)

        let loaded = try #require(try await store.player(id: player.id))
        #expect(loaded.displayName == "Juan Núñez")
        #expect(loaded.aliases == ["JIN", "Nuñez"])
        #expect(loaded.birthDate == PartialDate(year: 1999, month: 3))
        #expect(loaded.birthCountryID == argentina.id)
        #expect(Set(loaded.citizenshipIDs) == Set([argentina.id, italy.id]))
        #expect(loaded.positions.first { $0.isPrimary }?.position == .cb)
    }

    @Test func searchIgnoresCaseAndAccentsAndKeepsSameNamePlayersApart() async throws {
        let store = try makeStore()
        let first = Player(displayName: "José Pérez")
        let second = Player(displayName: "José Pérez")
        try await store.savePlayer(first)
        try await store.savePlayer(second)

        let found = try await store.playerList(search: "jose perez")
        #expect(Set(found.map(\.id)) == [first.id, second.id])
    }

    @Test func failedSaveLeavesNothingBehind() async throws {
        let store = try makeStore()
        let unknownCountry = CountryID()
        let player = Player(displayName: "Nobody", citizenshipIDs: [unknownCountry])

        await #expect(throws: DatabaseError.self) {
            try await store.savePlayer(player)
        }
        #expect(try await store.playerList(includeArchived: true).isEmpty)
    }

    @Test func archivedPlayersStayOutOfTheDefaultDirectory() async throws {
        let store = try makeStore()
        let player = Player(displayName: "Archived Ana")
        try await store.savePlayer(player)
        try await store.setPlayerArchived(player.id, isArchived: true)

        #expect(try await store.playerList().isEmpty)
        #expect(try await store.playerList(includeArchived: true).count == 1)
    }

    @Test func newClubGetsADefaultSeniorTeam() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)

        let teams = try await store.teams(clubID: club.id)
        #expect(teams.count == 1)
        #expect(teams.first?.category == .senior)

        try await store.saveTeam(Team(clubID: club.id, displayName: "Reserve", category: .reserve))
        #expect(try await store.clubList().first?.teamCount == 2)
    }

    @Test func legitimateSeniorAndReserveMembershipsCoexist() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)
        let reserve = Team(clubID: club.id, displayName: "Reserve", category: .reserve)
        try await store.saveTeam(reserve)
        let senior = try #require(try await store.teams(clubID: club.id).first)
        let player = Player(displayName: "Dual Registration")
        try await store.savePlayer(player)

        let start = PartialDate(year: 2025, month: 1, day: 1)
        try await store.saveMembership(RosterMembership(playerID: player.id, teamID: senior.id, startDate: start, shirtNumber: 9))
        try await store.saveMembership(RosterMembership(playerID: player.id, teamID: reserve.id, startDate: start, shirtNumber: 19))

        #expect(try await store.memberships(playerID: player.id).count == 2)
    }

    @Test func overlappingMembershipInTheSameTeamIsRefused() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)
        let team = try #require(try await store.teams(clubID: club.id).first)
        let player = Player(displayName: "Overlap Test")
        try await store.savePlayer(player)

        try await store.saveMembership(RosterMembership(
            playerID: player.id,
            teamID: team.id,
            startDate: PartialDate(year: 2020, month: 1, day: 1),
            endDate: PartialDate(year: 2022, month: 1, day: 1)
        ))
        await #expect(throws: DomainError.overlappingMembership) {
            try await store.saveMembership(RosterMembership(
                playerID: player.id,
                teamID: team.id,
                startDate: PartialDate(year: 2021, month: 1, day: 1)
            ))
        }
        #expect(try await store.memberships(playerID: player.id).count == 1)
    }

    @Test func reversedMembershipDatesAreRefusedWithoutAWrite() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)
        let team = try #require(try await store.teams(clubID: club.id).first)
        let player = Player(displayName: "Reversed Dates")
        try await store.savePlayer(player)

        await #expect(throws: DomainError.invalidInterval) {
            try await store.saveMembership(RosterMembership(
                playerID: player.id,
                teamID: team.id,
                startDate: PartialDate(year: 2024, month: 5, day: 1),
                endDate: PartialDate(year: 2023, month: 1, day: 1)
            ))
        }
        #expect(try await store.memberships(playerID: player.id).isEmpty)
    }

    @Test func endingAMembershipKeepsThePlayerAndHistory() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)
        let team = try #require(try await store.teams(clubID: club.id).first)
        let player = Player(displayName: "Leaves The Club")
        try await store.savePlayer(player)
        let membership = RosterMembership(
            playerID: player.id,
            teamID: team.id,
            startDate: PartialDate(year: 2020, month: 7, day: 1)
        )
        try await store.saveMembership(membership)

        let endDate = try #require(PartialDate(year: 2023, month: 6, day: 30))
        try await store.endMembership(membership.id, on: endDate)

        let entry = try #require(try await store.memberships(playerID: player.id).first)
        #expect(entry.membership.endDate == PartialDate(year: 2023, month: 6, day: 30))
        #expect(entry.membership.status == .former)
        #expect(try await store.player(id: player.id) != nil)
    }

    @Test func editingShirtNumberAndStatusKeepsTheDatesAndTheSameMembership() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)
        let team = try #require(try await store.teams(clubID: club.id).first)
        let player = Player(displayName: "Editable Shirt")
        try await store.savePlayer(player)
        let membership = RosterMembership(
            playerID: player.id,
            teamID: team.id,
            startDate: PartialDate(year: 2025, month: 1, day: 1),
            shirtNumber: 9
        )
        try await store.saveMembership(membership)

        var edited = membership
        edited.shirtNumber = 10
        edited.status = .uncertain
        try await store.saveMembership(edited)

        let saved = try #require(try await store.roster(teamID: team.id).first?.membership)
        #expect(saved.id == membership.id)
        #expect(saved.shirtNumber == 10)
        #expect(saved.status == .uncertain)
        #expect(saved.startDate?.storageText == membership.startDate?.storageText)
        #expect(try await store.memberships(playerID: player.id).count == 1)
    }

    @Test func invalidShirtNumberIsRefusedWithoutAWrite() async throws {
        let store = try makeStore()
        let club = Club(displayName: "Club Ejemplo")
        try await store.saveClub(club)
        let team = try #require(try await store.teams(clubID: club.id).first)
        let player = Player(displayName: "Bad Shirt")
        try await store.savePlayer(player)
        let membership = RosterMembership(playerID: player.id, teamID: team.id, shirtNumber: 9)
        try await store.saveMembership(membership)

        var edited = membership
        edited.shirtNumber = 100
        await #expect(throws: DomainError.invalidShirtNumber) {
            try await store.saveMembership(edited)
        }
        #expect(try await store.roster(teamID: team.id).first?.membership.shirtNumber == 9)
    }

    @Test func savedDataSurvivesReopeningTheFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("database.sqlite")
        let player = Player(displayName: "Persisted")

        do {
            let store = LibraryStore(database: try LibraryDatabase.open(at: url))
            try await store.savePlayer(player)
        }

        let reopened = LibraryStore(database: try LibraryDatabase.open(at: url))
        #expect(try await reopened.player(id: player.id)?.displayName == "Persisted")
    }
}
