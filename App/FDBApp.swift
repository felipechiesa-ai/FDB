import SwiftUI

@main
struct FDBApp: App {
    private let library: Result<LibraryModel, Error>

    init() {
        library = Result {
            LibraryModel(opened: try LibraryLocation.open())
        }
    }

    var body: some Scene {
        WindowGroup {
            switch library {
            case .success(let model):
                RootView()
                    .environment(model)
            case .failure(let error):
                ContentUnavailableView {
                    Label("The library could not be opened", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
    }
}
