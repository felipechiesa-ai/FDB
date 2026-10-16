import SwiftUI
import FDBDomain
import FDBPersistence

/// Create or edit a club. A new club also gets its first senior team.
struct ClubEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library

    let original: Club?
    let onSaved: (ClubID) -> Void

    @State private var draft: Club
    @State private var countries: [Country] = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(club: Club?, onSaved: @escaping (ClubID) -> Void) {
        original = club
        self.onSaved = onSaved
        _draft = State(initialValue: club ?? Club(displayName: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display name", text: $draft.displayName)
                    TextField("Official name", text: optionalText(\.officialName))
                    TextField("Short name", text: optionalText(\.shortName))
                }
                Section("Location and history") {
                    TextField("City", text: optionalText(\.city))
                    Picker("Country", selection: $draft.countryID) {
                        Text("Unknown").tag(CountryID?.none)
                        ForEach(countries) { country in
                            Text(country.displayName).tag(Optional(country.id))
                        }
                    }
                    PartialDateField(title: "Founded", value: $draft.foundedDate)
                }
                Section("Notes") {
                    TextEditor(text: optionalText(\.notes))
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(original == nil ? "New Club" : "Edit Club")
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
        .frame(minWidth: 520, minHeight: 600)
        .task { countries = (try? await library.store.countries()) ?? [] }
    }

    private func optionalText(_ keyPath: WritableKeyPath<Club, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func save() {
        let club = draft
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.store.saveClub(club)
                onSaved(club.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
