import SwiftUI
import UniformTypeIdentifiers
import FDBDomain
import FDBLibrary

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
    @State private var choosingBackupFolder = false
    @State private var choosingRestoreFolder = false
    @State private var restoreCandidate: URL?
    @State private var message: String?
    @State private var errorMessage: String?

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
            .toolbar {
                ToolbarItem {
                    Menu("Library", systemImage: "externaldrive") {
                        Button("Back Up Library…") { choosingBackupFolder = true }
                        Button("Restore Library…") { choosingRestoreFolder = true }
                    }
                }
            }
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
        .fileImporter(isPresented: $choosingBackupFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await backUp(to: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $choosingRestoreFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task { await prepareRestore(from: url) }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Replace the current library?", isPresented: restoreIsPresented, titleVisibility: .visible) {
            Button("Restore Backup", role: .destructive) {
                if let url = restoreCandidate {
                    Task { await restore(url) }
                }
            }
            Button("Cancel", role: .cancel) {
                restoreCandidate = nil
            }
        } message: {
            Text("The current library is replaced. A recovery copy of it is kept first.")
        }
        .alert("FDB", isPresented: messageIsPresented) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .overlay {
            if library.isRestoring || library.isBlocked {
                restoringOverlay
            }
        }
        .errorAlert($errorMessage)
    }

    /// Covers the window while a restore swaps the library. If the library cannot be reopened, the cover stays until relaunch.
    private var restoringOverlay: some View {
        ZStack {
            Color.black.opacity(0.2)
            Group {
                if library.isBlocked {
                    Label("The library could not be reopened. Quit and open FDB again.", systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView("Restoring library…")
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .ignoresSafeArea()
    }

    private var restoreIsPresented: Binding<Bool> {
        Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } })
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func backUp(to directory: URL) async {
        let accessed = directory.startAccessingSecurityScopedResource()
        defer { if accessed { directory.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try await LibraryBackup.create(from: library.store, folder: library.folder, in: directory)
            message = "Backup saved as \(backup.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareRestore(from url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            try await Task.detached(priority: .userInitiated) { _ = try LibraryBackup.validate(url) }.value
            restoreCandidate = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        restoreCandidate = nil
        do {
            let recovery = try await library.restore(
                from: url,
                recoveryDirectory: try LibraryLocation.recoveryDirectory()
            )
            message = "Library restored. The previous library is kept as \(recovery.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
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
