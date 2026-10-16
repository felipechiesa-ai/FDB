import SwiftUI
import FDBDomain
import FDBPersistence

/// One player's profile. Team memberships link to the team, and the team links back to the roster.
struct PlayerDetailView: View {
    @Environment(LibraryModel.self) private var library
    let playerID: PlayerID

    @State private var player: Player?
    @State private var memberships: [PlayerMembershipEntry] = []
    @State private var countryNames: [CountryID: String] = [:]
    @State private var isEditing = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let player {
                Form {
                    Section("Name") {
                        LabeledContent("Display name", value: player.displayName)
                        if let fullName = player.fullName {
                            LabeledContent("Full name", value: fullName)
                        }
                        if !player.aliases.isEmpty {
                            LabeledContent("Aliases", value: player.aliases.joined(separator: ", "))
                        }
                    }
                    Section("Biography") {
                        LabeledContent("Birth date", value: birthDateText(player))
                        if let city = player.birthCity {
                            LabeledContent("Birth city", value: city)
                        }
                        if let countryID = player.birthCountryID, let name = countryNames[countryID] {
                            LabeledContent("Birth country", value: name)
                        }
                        LabeledContent("Height", value: player.heightCm.map { "\($0) cm" } ?? "Unknown")
                        LabeledContent("Preferred foot", value: player.preferredFoot?.label ?? "Unknown")
                    }
                    Section("Citizenship") {
                        if player.citizenshipIDs.isEmpty {
                            Text("None listed").foregroundStyle(.secondary)
                        }
                        ForEach(player.citizenshipIDs, id: \.self) { countryID in
                            Text(countryNames[countryID] ?? "Unknown country")
                        }
                    }
                    Section("Positions") {
                        if player.positions.isEmpty {
                            Text("None listed").foregroundStyle(.secondary)
                        }
                        ForEach(player.positions, id: \.position) { assignment in
                            LabeledContent(assignment.position.label, value: assignment.isPrimary ? "Primary" : "Secondary")
                        }
                    }
                    Section("Teams") {
                        if memberships.isEmpty {
                            Text("No team memberships yet").foregroundStyle(.secondary)
                        }
                        ForEach(memberships) { entry in
                            NavigationLink(value: entry.membership.teamID) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.clubName) · \(entry.teamName)")
                                    Text(MembershipFormat.summary(entry.membership))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let notes = player.notes {
                        Section("Notes") {
                            Text(notes)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(player.displayName)
                .toolbar {
                    ToolbarItemGroup {
                        Button("Edit") { isEditing = true }
                        Button(player.isArchived ? "Unarchive" : "Archive") {
                            toggleArchive(player)
                        }
                    }
                }
            } else {
                ContentUnavailableView("Player not found", systemImage: "questionmark.circle")
            }
        }
        .task(id: library.revision) { await reload() }
        .sheet(isPresented: $isEditing) {
            PlayerEditorView(player: player) { _ in
                library.didChange()
            }
        }
        .errorAlert($errorMessage)
    }

    private func birthDateText(_ player: Player) -> String {
        guard let birthDate = player.birthDate else { return "Unknown" }
        var text = birthDate.formatted()
        if let age = player.age(on: Date()) {
            text += " (age \(age))"
        }
        return text
    }

    private func toggleArchive(_ player: Player) {
        Task {
            do {
                try await library.store.setPlayerArchived(player.id, isArchived: !player.isArchived)
                library.didChange()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() async {
        do {
            player = try await library.store.player(id: playerID)
            memberships = try await library.store.memberships(playerID: playerID)
            let countries = try await library.store.countries()
            countryNames = Dictionary(uniqueKeysWithValues: countries.map { ($0.id, $0.displayName) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
