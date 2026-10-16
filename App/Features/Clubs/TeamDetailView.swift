import SwiftUI
import FDBDomain
import FDBPersistence

/// One team's roster. Players link to their profile; ending a membership keeps the player and history.
struct TeamDetailView: View {
    @Environment(LibraryModel.self) private var library
    let teamID: TeamID

    @State private var team: Team?
    @State private var clubName = ""
    @State private var roster: [RosterEntry] = []
    @State private var isAddingPlayer = false
    @State private var isEditingTeam = false
    @State private var endingEntry: RosterEntry?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let team {
                List {
                    Section {
                        LabeledContent("Club", value: clubName)
                        LabeledContent("Category", value: team.category.label)
                        LabeledContent("Gender", value: team.genderCategory.label)
                        if let ageGroup = team.ageGroup {
                            LabeledContent("Age group", value: ageGroup)
                        }
                    }
                    Section("Roster") {
                        if roster.isEmpty {
                            Text("No players in this team yet")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(roster) { entry in
                            NavigationLink(value: entry.membership.playerID) {
                                RosterRow(entry: entry)
                            }
                            .contextMenu {
                                if entry.membership.endDate == nil {
                                    Button("End Membership…") { endingEntry = entry }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(team.displayName)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Edit Team") { isEditingTeam = true }
                        Button("Add Player", systemImage: "person.badge.plus") { isAddingPlayer = true }
                    }
                }
            } else {
                ContentUnavailableView("Team not found", systemImage: "questionmark.circle")
            }
        }
        .task(id: library.revision) { await reload() }
        .sheet(isPresented: $isAddingPlayer) {
            if let team {
                MembershipEditorView(team: team) {
                    library.didChange()
                }
            }
        }
        .sheet(isPresented: $isEditingTeam) {
            if let team {
                TeamEditorView(clubID: team.clubID, team: team) {
                    library.didChange()
                }
            }
        }
        .sheet(item: $endingEntry) { entry in
            EndMembershipSheet(entry: entry)
        }
        .errorAlert($errorMessage)
    }

    private func reload() async {
        do {
            team = try await library.store.team(id: teamID)
            if let clubID = team?.clubID {
                clubName = try await library.store.club(id: clubID)?.displayName ?? ""
            }
            roster = try await library.store.roster(teamID: teamID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RosterRow: View {
    let entry: RosterEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.membership.shirtNumber.map { "\($0)" } ?? "–")
                .font(.body.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.playerName)
                    if entry.playerIsArchived {
                        Text("Archived")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(MembershipFormat.summary(entry.membership))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
