import XCTest

final class FDBUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchShowsMainWindow() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    /// The demo players appear in the directory.
    @MainActor
    func testDemoPlayersDirectoryListsSeededPlayers() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FDBDemoLibrary"]
        app.launch()

        XCTAssertTrue(text(app, "Lucas Ferrer").waitForExistence(timeout: 10))
        XCTAssertTrue(text(app, "Tomás Gil").exists)
        attachScreenshot(app, named: "players-directory")
    }

    /// The first demo club shows its city and founding year.
    @MainActor
    func testDemoClubProfileShowsDetails() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FDBDemoLibrary", "-FDBStartSection", "clubs", "-FDBSelectFirst"]
        app.launch()

        _ = text(app, "Villa Modelo").waitForExistence(timeout: 10)
        attachScreenshot(app, named: "club-profile")
        XCTAssertTrue(text(app, "Villa Modelo").exists)
        XCTAssertTrue(text(app, "1921").exists)
    }

    /// The first demo player shows biography and citizenship.
    @MainActor
    func testDemoPlayerProfileShowsBiography() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-FDBDemoLibrary", "-FDBSelectFirst"]
        app.launch()

        _ = text(app, "Argentina").waitForExistence(timeout: 10)
        attachScreenshot(app, named: "player-profile")
        XCTAssertTrue(text(app, "Argentina").exists)
        XCTAssertTrue(text(app, "Left").exists)
    }

    /// Static text is matched by its displayed value, which is what the accessibility tree exposes here.
    private func text(_ app: XCUIApplication, _ value: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "value == %@", value)).firstMatch
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
