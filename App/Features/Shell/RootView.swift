import SwiftUI
import FDBDomain

enum LibrarySection: String, CaseIterable, Identifiable {
    case players
    case clubs

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .players: "Players"
        case .clubs: "Clubs"
        }
    }

    var systemImage: String {
        switch self {
        case .players: "person.2"
        case .clubs: "sportscourt"
        }
    }
}

/// Three columns: sections, the directory for the section, and a detail stack that can drill into teams and players.
struct RootView: View {
    @Environment(LibraryModel.self) private var library
    @State private var section: LibrarySection? = RootView.launchSection
    @State private var selectedPlayer: PlayerID?
    @State private var selectedClub: ClubID?

    /// Developer launch argument `-FDBStartSection players|clubs` opens the library on that section.
    static var launchSection: LibrarySection {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-FDBStartSection"),
              arguments.indices.contains(index + 1),
              let section = LibrarySection(rawValue: arguments[index + 1]) else {
            return .players
        }
        return section
    }


    var body: some View {
        NavigationSplitView {
            List(LibrarySection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationTitle("FDB")
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } content: {
            switch section {
            case .players:
                PlayersView(selection: $selectedPlayer)
            case .clubs:
                ClubsView(selection: $selectedClub)
            case nil:
                ContentUnavailableView("Choose a section", systemImage: "sidebar.left")
            }
        } detail: {
            NavigationStack {
                detail
                    .navigationDestination(for: PlayerID.self) { PlayerDetailView(playerID: $0) }
                    .navigationDestination(for: TeamID.self) { TeamDetailView(teamID: $0) }
                    .navigationDestination(for: ClubID.self) { ClubDetailView(clubID: $0) }
            }
        }
        .task {
            guard LibraryLocation.isDemo else { return }
            try? await DemoLibrary.seedIfEmpty(library.store)
            library.didChange()
            if CommandLine.arguments.contains("-FDBSelectFirst") {
                await selectFirstItem()
            }
        }
    }

    /// Developer launch argument `-FDBSelectFirst` opens the first player or club, for screenshots and demos.
    private func selectFirstItem() async {
        switch section {
        case .players:
            selectedPlayer = try? await library.store.playerList().first?.id
        case .clubs:
            selectedClub = try? await library.store.clubList().first?.id
        case nil:
            break
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .players:
            if let selectedPlayer {
                PlayerDetailView(playerID: selectedPlayer)
                    .id(selectedPlayer)
            } else {
                ContentUnavailableView("Select a player", systemImage: "person")
            }
        case .clubs:
            if let selectedClub {
                ClubDetailView(clubID: selectedClub)
                    .id(selectedClub)
            } else {
                ContentUnavailableView("Select a club", systemImage: "sportscourt")
            }
        case nil:
            EmptyView()
        }
    }
}
