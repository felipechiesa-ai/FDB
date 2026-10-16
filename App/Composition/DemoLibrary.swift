import FDBDomain
import FDBPersistence

/// Fictional records for developers. Seeded only into the separate demo library, and only when it is empty.
enum DemoLibrary {
    static func seedIfEmpty(_ store: LibraryStore) async throws {
        guard try await store.playerList(includeArchived: true).isEmpty else { return }
        let countries = try await store.countries()
        func countryID(_ code: String) -> CountryID? {
            countries.first { $0.isoCode == code }?.id
        }

        let mainClub = Club(
            displayName: "Club Ejemplo",
            city: "Villa Modelo",
            countryID: countryID("AR"),
            foundedDate: PartialDate(year: 1921)
        )
        try await store.saveClub(mainClub)
        try await store.saveClub(Club(displayName: "Deportivo Modelo", city: "Puerto Ficticio", countryID: countryID("AR")))

        let teams = try await store.teams(clubID: mainClub.id)
        guard let senior = teams.first(where: { $0.category == .senior }) else { return }
        let reserve = Team(clubID: mainClub.id, displayName: "Reserve", category: .reserve)
        try await store.saveTeam(reserve)

        let mateo = Player(
            displayName: "Mateo Ruiz",
            birthDate: PartialDate(year: 1999, month: 3, day: 14),
            birthCity: "Villa Modelo",
            birthCountryID: countryID("AR"),
            heightCm: 184,
            preferredFoot: .right,
            citizenshipIDs: [countryID("AR"), countryID("IT")].compactMap { $0 },
            positions: [PlayerPositionAssignment(position: .cb, isPrimary: true)]
        )
        let lucas = Player(
            displayName: "Lucas Ferrer",
            birthDate: PartialDate(year: 2003),
            preferredFoot: .left,
            citizenshipIDs: [countryID("AR")].compactMap { $0 },
            positions: [
                PlayerPositionAssignment(position: .cf, isPrimary: true),
                PlayerPositionAssignment(position: .lw)
            ]
        )
        let namesake = Player(
            displayName: "Mateo Ruiz",
            birthDate: PartialDate(year: 2001, month: 11, day: 2),
            citizenshipIDs: [countryID("ES")].compactMap { $0 },
            positions: [PlayerPositionAssignment(position: .gk, isPrimary: true)]
        )
        let tomas = Player(displayName: "Tomás Gil")
        for player in [mateo, lucas, namesake, tomas] {
            try await store.savePlayer(player)
        }

        try await store.saveMembership(RosterMembership(
            playerID: mateo.id,
            teamID: reserve.id,
            startDate: PartialDate(year: 2022, month: 7, day: 1),
            endDate: PartialDate(year: 2024, month: 7, day: 1),
            shirtNumber: 25,
            status: .former
        ))
        try await store.saveMembership(RosterMembership(
            playerID: mateo.id,
            teamID: senior.id,
            startDate: PartialDate(year: 2024, month: 7, day: 1),
            shirtNumber: 5
        ))
        try await store.saveMembership(RosterMembership(
            playerID: lucas.id,
            teamID: reserve.id,
            startDate: PartialDate(year: 2025, month: 2, day: 1),
            shirtNumber: 9
        ))
    }
}
