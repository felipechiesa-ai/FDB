import Foundation
import Testing
@testable import FDBDomain

struct PartialDateTests {
    @Test func rejectsDatesThatDoNotExist() {
        #expect(PartialDate(year: 2026, month: 2, day: 30) == nil)
        #expect(PartialDate(year: 2026, month: 13) == nil)
        #expect(PartialDate(year: 2026, day: 5) == nil)
    }

    @Test func acceptsLeapDaysOnlyInLeapYears() {
        #expect(PartialDate(year: 2028, month: 2, day: 29) != nil)
        #expect(PartialDate(year: 2027, month: 2, day: 29) == nil)
    }

    @Test func roundTripsStorageText() throws {
        for text in ["1998", "1998-07", "1998-07-14"] {
            let date = try #require(PartialDate(storageText: text))
            #expect(date.storageText == text)
        }
    }

    @Test func neverInventsMissingParts() throws {
        let year = try #require(PartialDate(year: 1998))
        #expect(year.precision == .year)
        #expect(year.month == nil)
        #expect(year.day == nil)
    }
}

struct PlayerRuleTests {
    @Test func requiresADisplayName() {
        #expect(throws: DomainError.emptyName) {
            try Player(displayName: "   ").validate()
        }
    }

    @Test func allowsOnlyOnePrimaryPosition() {
        let player = Player(displayName: "Ana", positions: [
            PlayerPositionAssignment(position: .cb, isPrimary: true),
            PlayerPositionAssignment(position: .cm, isPrimary: true)
        ])
        #expect(throws: DomainError.multiplePrimaryPositions) {
            try player.validate()
        }
    }

    @Test func rejectsHeightOutsideTheSupportedRange() {
        #expect(throws: DomainError.invalidHeight) {
            try Player(displayName: "Ana", heightCm: 300).validate()
        }
    }

    @Test func givesNoAgeWithoutAnExactBirthDate() {
        let player = Player(displayName: "Ana", birthDate: PartialDate(year: 2000))
        #expect(player.age(on: Date()) == nil)
    }

    @Test func computesAgeFromAnExactBirthDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let player = Player(displayName: "Ana", birthDate: PartialDate(year: 2000, month: 6, day: 15))
        let dayBefore = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 14)))
        let birthday = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 15)))
        #expect(player.age(on: dayBefore, calendar: calendar) == 25)
        #expect(player.age(on: birthday, calendar: calendar) == 26)
    }
}

struct RosterMembershipTests {
    private let player = PlayerID()
    private let team = TeamID()

    @Test func rejectsReversedExactDates() {
        let membership = RosterMembership(
            playerID: player,
            teamID: team,
            startDate: PartialDate(year: 2021, month: 5, day: 1),
            endDate: PartialDate(year: 2020, month: 1, day: 1)
        )
        #expect(throws: DomainError.invalidInterval) {
            try membership.validate()
        }
    }

    @Test func rejectsAnEmptyExactRange() {
        let day = PartialDate(year: 2020, month: 1, day: 1)
        let membership = RosterMembership(playerID: player, teamID: team, startDate: day, endDate: day)
        #expect(throws: DomainError.invalidInterval) {
            try membership.validate()
        }
    }

    @Test func acceptsPartialDatesWithoutInventingExactOnes() throws {
        let membership = RosterMembership(
            playerID: player,
            teamID: team,
            startDate: PartialDate(year: 2019),
            endDate: PartialDate(year: 2021, month: 6)
        )
        try membership.validate()
    }

    @Test func treatsTheEndDateAsExclusive() {
        let first = RosterMembership(
            playerID: player,
            teamID: team,
            startDate: PartialDate(year: 2020, month: 1, day: 1),
            endDate: PartialDate(year: 2021, month: 1, day: 1)
        )
        let next = RosterMembership(
            playerID: player,
            teamID: team,
            startDate: PartialDate(year: 2021, month: 1, day: 1)
        )
        #expect(!first.overlaps(next))
        #expect(!next.overlaps(first))
    }

    @Test func detectsOverlappingSpans() {
        let first = RosterMembership(
            playerID: player,
            teamID: team,
            startDate: PartialDate(year: 2020, month: 1, day: 1),
            endDate: PartialDate(year: 2021, month: 6, day: 1)
        )
        let second = RosterMembership(
            playerID: player,
            teamID: team,
            startDate: PartialDate(year: 2021, month: 1, day: 1)
        )
        #expect(first.overlaps(second))
    }

    @Test func rejectsShirtNumbersOutsideRange() {
        let membership = RosterMembership(playerID: player, teamID: team, shirtNumber: 100)
        #expect(throws: DomainError.invalidShirtNumber) {
            try membership.validate()
        }
    }
}

struct SearchTextTests {
    @Test func foldsCaseAndAccents() {
        #expect(SearchText.fold("José Núñez") == SearchText.fold("jose nunez"))
    }
}
