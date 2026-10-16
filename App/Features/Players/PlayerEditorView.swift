import SwiftUI
import FDBDomain
import FDBPersistence

/// Create or edit a player. Edits stay in a draft until Save succeeds; Cancel leaves the library unchanged.
struct PlayerEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryModel.self) private var library

    let original: Player?
    let onSaved: (PlayerID) -> Void

    @State private var draft: Player
    @State private var aliasesText: String
    @State private var heightText: String
    @State private var countries: [Country] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var confirmingDiscard = false

    private let originalAliasesText: String
    private let originalHeightText: String

    init(player: Player?, onSaved: @escaping (PlayerID) -> Void) {
        let initial = player ?? Player(displayName: "")
        original = player
        self.onSaved = onSaved
        originalAliasesText = initial.aliases.joined(separator: "\n")
        originalHeightText = initial.heightCm.map(String.init) ?? ""
        _draft = State(initialValue: initial)
        _aliasesText = State(initialValue: originalAliasesText)
        _heightText = State(initialValue: originalHeightText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Display name", text: $draft.displayName)
                    TextField("Full name", text: optionalText(\.fullName))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aliases, one per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $aliasesText)
                            .frame(minHeight: 60)
                    }
                }
                Section("Biography") {
                    PartialDateField(title: "Birth date", value: $draft.birthDate)
                    TextField("Birth city", text: optionalText(\.birthCity))
                    Picker("Birth country", selection: $draft.birthCountryID) {
                        Text("Unknown").tag(CountryID?.none)
                        ForEach(countries) { country in
                            Text(country.displayName).tag(Optional(country.id))
                        }
                    }
                    TextField("Height (cm)", text: $heightText)
                    Picker("Preferred foot", selection: $draft.preferredFoot) {
                        Text("Unknown").tag(PreferredFoot?.none)
                        ForEach(PreferredFoot.allCases, id: \.self) { foot in
                            Text(foot.label).tag(Optional(foot))
                        }
                    }
                }
                Section("Citizenship") {
                    ForEach(citizenshipCountries) { country in
                        HStack {
                            Text(country.displayName)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle") {
                                draft.citizenshipIDs.removeAll { $0 == country.id }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                    Menu("Add citizenship") {
                        ForEach(availableCitizenships) { country in
                            Button(country.displayName) {
                                draft.citizenshipIDs.append(country.id)
                            }
                        }
                    }
                }
                Section("Positions") {
                    ForEach(draft.positions, id: \.position) { assignment in
                        HStack {
                            Text(assignment.position.label)
                            Spacer()
                            if assignment.isPrimary {
                                Text("Primary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Make Primary") { makePrimary(assignment.position) }
                                    .buttonStyle(.borderless)
                            }
                            Button("Remove", systemImage: "minus.circle") {
                                draft.positions.removeAll { $0.position == assignment.position }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                    Menu("Add position") {
                        ForEach(availablePositions, id: \.self) { position in
                            Button(position.label) {
                                draft.positions.append(PlayerPositionAssignment(
                                    position: position,
                                    isPrimary: draft.positions.isEmpty
                                ))
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextEditor(text: optionalText(\.notes))
                        .frame(minHeight: 80)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(original == nil ? "New Player" : "Edit Player")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .errorAlert($errorMessage)
        }
        .frame(minWidth: 540, minHeight: 640)
        .task { countries = (try? await library.store.countries()) ?? [] }
    }

    private var hasChanges: Bool {
        guard let original else {
            return !draft.displayName.isEmpty || !aliasesText.isEmpty || !heightText.isEmpty
        }
        return draft != original || aliasesText != originalAliasesText || heightText != originalHeightText
    }

    private var citizenshipCountries: [Country] {
        draft.citizenshipIDs.compactMap { id in countries.first { $0.id == id } }
    }

    private var availableCitizenships: [Country] {
        countries.filter { !draft.citizenshipIDs.contains($0.id) }
    }

    private var availablePositions: [PlayerPosition] {
        let assigned = Set(draft.positions.map(\.position))
        return PlayerPosition.allCases.filter { !assigned.contains($0) }
    }

    private func optionalText(_ keyPath: WritableKeyPath<Player, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func makePrimary(_ position: PlayerPosition) {
        draft.positions = draft.positions.map {
            PlayerPositionAssignment(position: $0.position, isPrimary: $0.position == position)
        }
    }

    private func requestCancel() {
        if hasChanges {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        var candidate = draft
        candidate.aliases = aliasesText.split(whereSeparator: \.isNewline).map { String($0) }
        do {
            candidate.heightCm = try parsedHeight()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.store.savePlayer(candidate)
                onSaved(candidate.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func parsedHeight() throws -> Int? {
        let text = heightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard let height = Int(text) else { throw DomainError.invalidHeight }
        return height
    }
}
