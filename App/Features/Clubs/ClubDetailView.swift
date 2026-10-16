import SwiftUI
import FDBDomain
import FDBPersistence

/// One club: its details and teams. Each team opens its roster.
struct ClubDetailView: View {
    @Environment(LibraryModel.self) private var library
    let clubID: ClubID

    @State private var club: Club?
    @State private var countryName: String?
    @State private var teams: [Team] = []
    @State private var isEditing = false
    @State private var isAddingTeam = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let club {
                Form {
                    Section("Club") {
                        if let officialName = club.officialName {
                            LabeledContent("Official name", value: officialName)
                        }
                        if let shortName = club.shortName {
                            LabeledContent("Short name", value: shortName)
                        }
                        if let city = club.city {
                            LabeledContent("City", value: city)
                        }
                        if let countryName {
                            LabeledContent("Country", value: countryName)
                        }
                        if let founded = club.foundedDate {
                            LabeledContent("Founded", value: founded.formatted())
                        }
                    }
                    Section("Teams") {
                        if teams.isEmpty {
                            Text("No teams yet").foregroundStyle(.secondary)
                        }
                        ForEach(teams) { team in
                            NavigationLink(value: team.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(team.displayName)
                                    Text(teamDetails(team))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Add Team", systemImage: "plus") { isAddingTeam = true }
                    }
                    if let notes = club.notes {
                        Section("Notes") {
                            Text(notes)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(club.displayName)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Edit") { isEditing = true }
                        Button(club.isArchived ? "Unarchive" : "Archive") { toggleArchive() }
                    }
                }
            } else {
                ContentUnavailableView("Club not found", systemImage: "questionmark.circle")
            }
        }
        .task(id: library.revision) { await reload() }
        .sheet(isPresented: $isEditing) {
            ClubEditorView(club: club) { _ in
                library.didChange()
            }
        }
        .sheet(isPresented: $isAddingTeam) {
            TeamEditorView(clubID: clubID, team: nil) {
                library.didChange()
            }
        }
        .errorAlert($errorMessage)
    }

    private func teamDetails(_ team: Team) -> String {
        [team.category.label, team.genderCategory.label, team.ageGroup]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func toggleArchive() {
        guard let club else { return }
        Task {
            do {
                try await library.store.setClubArchived(club.id, isArchived: !club.isArchived)
                library.didChange()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() async {
        do {
            club = try await library.store.club(id: clubID)
            teams = try await library.store.teams(clubID: clubID)
            if let countryID = club?.countryID {
                let countries = try await library.store.countries()
                countryName = countries.first { $0.id == countryID }?.displayName
            } else {
                countryName = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
