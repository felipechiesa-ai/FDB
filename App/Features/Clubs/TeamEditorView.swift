import SwiftUI
import FDBDomain
import FDBPersistence

/// Create or edit a team within a club. Category and gender are controlled codes, not inferred from the name.
struct TeamEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library

    let clubID: ClubID
    let team: Team?
    let onSaved: () -> Void

    @State private var displayName: String
    @State private var category: TeamCategory
    @State private var genderCategory: GenderCategory
    @State private var ageGroup: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(clubID: ClubID, team: Team?, onSaved: @escaping () -> Void) {
        self.clubID = clubID
        self.team = team
        self.onSaved = onSaved
        _displayName = State(initialValue: team?.displayName ?? "")
        _category = State(initialValue: team?.category ?? .reserve)
        _genderCategory = State(initialValue: team?.genderCategory ?? .unspecified)
        _ageGroup = State(initialValue: team?.ageGroup ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Team name", text: $displayName)
                    Picker("Category", selection: $category) {
                        ForEach(TeamCategory.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Picker("Gender", selection: $genderCategory) {
                        ForEach(GenderCategory.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    TextField("Age group (optional, e.g. U19)", text: $ageGroup)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(team == nil ? "New Team" : "Edit Team")
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
        .frame(minWidth: 460, minHeight: 360)
    }

    private func save() {
        let candidate = Team(
            id: team?.id ?? TeamID(),
            clubID: clubID,
            displayName: displayName,
            category: category,
            ageGroup: ageGroup.isEmpty ? nil : ageGroup,
            genderCategory: genderCategory,
            isArchived: team?.isArchived ?? false,
            createdAt: team?.createdAt ?? Date(),
            updatedAt: Date()
        )
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.store.saveTeam(candidate)
                onSaved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
