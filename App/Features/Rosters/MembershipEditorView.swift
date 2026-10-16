import SwiftUI
import FDBDomain
import FDBPersistence

/// Adds a player to a team with dates, shirt number, and status. Overlapping memberships in the same team are refused.
struct MembershipEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library

    let team: Team
    let onSaved: () -> Void

    @State private var playerSearch = ""
    @State private var results: [PlayerListItem] = []
    @State private var selectedPlayer: PlayerListItem?
    @State private var startDate: PartialDate?
    @State private var endDate: PartialDate?
    @State private var shirtText = ""
    @State private var status: MembershipStatus = .current
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Player") {
                    LabeledContent("Player", value: selectedPlayer?.displayName ?? "Not chosen")
                    TextField("Search players", text: $playerSearch)
                    if results.isEmpty {
                        Text(playerSearch.isEmpty ? "No active players yet" : "No players match this search")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(results) { player in
                        Button {
                            selectedPlayer = player
                        } label: {
                            HStack {
                                Text(player.displayName)
                                Spacer()
                                if selectedPlayer?.id == player.id {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPlayer?.id == player.id ? .isSelected : [])
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
        .task(id: playerSearch) { await searchPlayers() }
    }

    /// Runs as the search text changes. A new keystroke cancels the previous run, and a short pause keeps the
    /// list from being rebuilt on every key. A cancelled search never replaces the list.
    private func searchPlayers() async {
        let query = playerSearch
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        do {
            let found = try await library.store.playerList(search: query)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let selectedPlayer else {
            errorMessage = "Choose a player."
            return
        }
        let membership: RosterMembership
        do {
            membership = RosterMembership(
                playerID: selectedPlayer.id,
                teamID: team.id,
                startDate: startDate,
                endDate: endDate,
                shirtNumber: try MembershipFormat.shirtNumber(from: shirtText),
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
}

/// Changes a membership's shirt number and status. The player, the team, and the dates stay as recorded.
struct EditMembershipSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library

    let membership: RosterMembership
    let playerName: String
    let teamName: String

    @State private var shirtText: String
    @State private var status: MembershipStatus
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(membership: RosterMembership, playerName: String, teamName: String) {
        self.membership = membership
        self.playerName = playerName
        self.teamName = teamName
        _shirtText = State(initialValue: membership.shirtNumber.map { "\($0)" } ?? "")
        _status = State(initialValue: membership.status)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Player", value: playerName)
                    LabeledContent("Team", value: teamName)
                }
                Section {
                    TextField("Shirt number", text: $shirtText)
                    Picker("Status", selection: $status) {
                        ForEach(MembershipStatus.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Membership")
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
        .frame(minWidth: 420, minHeight: 320)
    }

    private func save() {
        var updated = membership
        do {
            updated.shirtNumber = try MembershipFormat.shirtNumber(from: shirtText)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        updated.status = status

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.store.saveMembership(updated)
                library.didChange()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
