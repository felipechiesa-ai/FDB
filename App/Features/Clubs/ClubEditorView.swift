import SwiftUI
import UniformTypeIdentifiers
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
    @State private var badgeFileName: String?
    @State private var badgeChange: MediaChange = .unchanged
    @State private var choosingBadge = false
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
                Section("Badge") {
                    HStack(alignment: .center, spacing: 16) {
                        MediaThumbnailView(fileName: badgeFileName, placeholder: "shield", size: 96)
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Choose Image…") { choosingBadge = true }
                            if badgeFileName != nil {
                                Button("Remove Image", role: .destructive) {
                                    badgeFileName = nil
                                    badgeChange = .remove
                                }
                            }
                            Text("JPEG or PNG, up to 25 MB.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
            .fileImporter(isPresented: $choosingBadge, allowedContentTypes: [.jpeg, .png]) { result in
                guard case .success(let url) = result else {
                    if case .failure(let error) = result { errorMessage = error.localizedDescription }
                    return
                }
                Task {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let asset = try await library.importImage(from: url)
                        badgeChange = .set(asset)
                        badgeFileName = asset.fileName
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .errorAlert($errorMessage)
        }
        .frame(minWidth: 520, minHeight: 600)
        .task {
            countries = (try? await library.store.countries()) ?? []
            badgeFileName = try? await library.store.badge(for: draft.id)?.fileName
        }
    }

    private func optionalText(_ keyPath: WritableKeyPath<Club, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func save() {
        let club = draft
        let badge = badgeChange
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await library.store.saveClub(club, badge: badge)
                onSaved(club.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
