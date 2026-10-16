import Observation
import FDBPersistence

/// Shared app state: the open store, plus a revision counter that tells open screens to reload after a write.
@MainActor
@Observable
final class LibraryModel {
    let store: LibraryStore
    private(set) var revision = 0

    init(store: LibraryStore) {
        self.store = store
    }

    func didChange() {
        revision += 1
    }
}
