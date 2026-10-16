import SwiftUI
import FDBDomain
import FDBPersistence

/// Players directory: searchable, filterable by position, and sorted by name.
struct PlayersView: View {
    @Environment(LibraryModel.self) private var library
    @Binding var selection: PlayerID?

    @State private var search = ""
    @State private var position: PlayerPosition?
    @State private var includeArchived = false
    @State private var items: [PlayerListItem] = []
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var reloadKey: ReloadKey {
        ReloadKey(search: search, position: position, includeArchived: includeArchived, revision: library.revision)
    }

    var body: some View {
        List(items, selection: $selection) { item in
            PlayerRow(item: item)
        }
        .overlay { emptyState }
        .navigationTitle("Players")
        .searchable(text: $search, prompt: "Name or alias")
        .toolbar {
            ToolbarItemGroup {
                Picker("Position", selection: $position) {
                    Text("All positions").tag(PlayerPosition?.none)
                    ForEach(PlayerPosition.allCases, id: \.self) { option in
                        Text(option.label).tag(Optional(option))
                    }
                }
                Toggle("Show archived", isOn: $includeArchived)
                Button("New Player", systemImage: "plus") { isAdding = true }
            }
        }
        .task(id: reloadKey) { await reload() }
        .sheet(isPresented: $isAdding) {
            PlayerEditorView(player: nil) { id in
                selection = id
                library.didChange()
            }
        }
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private var emptyState: some View {
        if items.isEmpty {
            if search.isEmpty, position == nil, !includeArchived {
                ContentUnavailableView {
                    Label("No players yet", systemImage: "person.2")
                } description: {
                    Text("Add a player to start the library.")
                } actions: {
                    Button("New Player") { isAdding = true }
                }
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private func reload() async {
        do {
            items = try await library.store.playerList(
                search: search,
                position: position,
                includeArchived: includeArchived
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReloadKey: Hashable {
    let search: String
    let position: PlayerPosition?
    let includeArchived: Bool
    let revision: Int
}

struct PlayerRow: View {
    let item: PlayerListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.displayName)
                if item.isArchived {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var details: String {
        [item.primaryPosition?.label, item.birthDate?.formatted()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
