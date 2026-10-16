import SwiftUI
import FDBDomain
import FDBPersistence

/// Clubs directory: searchable by name, city, or official name.
struct ClubsView: View {
    @Environment(LibraryModel.self) private var library
    @Binding var selection: ClubID?

    @State private var search = ""
    @State private var includeArchived = false
    @State private var items: [ClubListItem] = []
    @State private var isAdding = false
    @State private var errorMessage: String?

    private var reloadKey: ClubReloadKey {
        ClubReloadKey(search: search, includeArchived: includeArchived, revision: library.revision)
    }

    var body: some View {
        List(items, selection: $selection) { item in
            ClubRow(item: item)
        }
        .overlay { emptyState }
        .navigationTitle("Clubs")
        .searchable(text: $search, prompt: "Club name or city")
        .toolbar {
            ToolbarItemGroup {
                Toggle("Show archived", isOn: $includeArchived)
                Button("New Club", systemImage: "plus") { isAdding = true }
            }
        }
        .task(id: reloadKey) { await reload() }
        .sheet(isPresented: $isAdding) {
            ClubEditorView(club: nil) { id in
                selection = id
                library.didChange()
            }
        }
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private var emptyState: some View {
        if items.isEmpty {
            if search.isEmpty, !includeArchived {
                ContentUnavailableView {
                    Label("No clubs yet", systemImage: "sportscourt")
                } description: {
                    Text("Add a club. It starts with one senior team.")
                } actions: {
                    Button("New Club") { isAdding = true }
                }
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
    }

    private func reload() async {
        do {
            items = try await library.store.clubList(search: search, includeArchived: includeArchived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ClubReloadKey: Hashable {
    let search: String
    let includeArchived: Bool
    let revision: Int
}

struct ClubRow: View {
    let item: ClubListItem

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
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var details: String {
        let teams = item.teamCount == 1 ? "1 team" : "\(item.teamCount) teams"
        return [item.city, item.countryName, teams]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
