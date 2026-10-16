import SwiftUI
import FDBDomain
import FDBPersistence

/// Adds a player to a team with dates, shirt number, and status. Overlapping memberships in the same team are refused.
struct MembershipEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library

    let team: Team
    let onSaved: () -> Void

    @State private var players: [PlayerListItem] = []
    @State private var playerSearch = ""
    @State private var playerID: PlayerID?
    @State private var startDate: PartialDate?
    @State private var endDate: PartialDate?
    @State private var shirtText = ""
    @State private var status: MembershipStatus = .current
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var filteredPlayers: [PlayerListItem] {
        let query = SearchText.fold(playerSearch.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return players }
        return players.filter { SearchText.fold($0.displayName).contains(query) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    TextField("Search players", text: $playerSearch)
                    Picker("Player", selection: $playerID) {
                        Text("Choose a player").tag(PlayerID?.none)
                        ForEach(filteredPlayers) { player in
                            Text(player.displayName).tag(Optional(player.id))
                        }
                    }
                }
                Section("Dates") {
                    PartialDateField(title: "Joined", value: $startDate)
                    PartialDateField(title: "First day not on the roster", value: $endDate)
                }
                Section("Details") {
                    TextField("Shirt number", text: $shirtText)
                    Picker("Status", selection: $status) {
                        ForEach(MembershipStatus.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add to \(team.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .errorAlert($errorMessage)
        }
        .frame(minWidth: 520, minHeight: 620)
        .task { await loadPlayers() }
    }

    private func loadPlayers() async {
        do {
            players = try await library.store.playerList()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let playerID else {
            errorMessage = "Choose a player."
            return
        }
        let membership: RosterMembership
        do {
            membership = RosterMembership(
                playerID: playerID,
                teamID: team.id,
                startDate: startDate,
                endDate: endDate,
                shirtNumber: try parsedShirtNumber(),
                status: status,
                notes: notes
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.store.saveMembership(membership)
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func parsedShirtNumber() throws -> Int? {
        let text = shirtText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let number = Int(text) else { throw DomainError.invalidShirtNumber }
        return number
    }
}

/// Removes a player from a roster by ending the membership. The player and history stay in the library.
struct EndMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library
    let entry: RosterEntry

    @State private var endDate: PartialDate? = EndMembershipSheet.today()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(entry.playerName) leaves this roster. The player and their history stay in the library.")
                }
                Section {
                    PartialDateField(title: "First day not on the roster", value: $endDate)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("End Membership")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End Membership") { save() }
                        .disabled(endDate == nil)
                }
            }
            .errorAlert($errorMessage)
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private static func today() -> PartialDate? {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return PartialDate(year: parts.year ?? 1970, month: parts.month, day: parts.day)
    }

    private func save() {
        guard let endDate else { return }
        Task {
            do {
                try await library.store.endMembership(entry.membership.id, on: endDate)
                library.didChange()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
