import XCTest

final class OffScriptUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingFirstScreenSmoke() throws {
        let app = makeApp(hasSeenOnboarding: false)
        app.launch()

        XCTAssertTrue(app.staticTexts["SIGNAL ACQUIRED"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "No algorithm pushing").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["POWER ON →"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testPostOnboardingShellSmoke() throws {
        let app = makeApp(hasSeenOnboarding: true)
        app.launch()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Queue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 10))

        app.buttons["Library"].tap()
        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 10))

        app.buttons["Queue"].tap()
        XCTAssertTrue(app.screen("QueueScreen").waitForExistence(timeout: 10))

        app.buttons["Search"].tap()
        XCTAssertTrue(app.screen("SearchScreen").waitForExistence(timeout: 10))

        app.buttons["Home"].tap()
        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 10))
    }

    @MainActor
    func testLargeLibrarySeedSmoke() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 258, debugEpisodesPerShow: 3, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "258").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 8))
    }

    private func makeApp(
        hasSeenOnboarding: Bool,
        debugLibrarySize: Int = 0,
        debugEpisodesPerShow: Int = 0,
        debugLaunchTab: Int = 0
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offscript.hasSeenOnboarding",
            hasSeenOnboarding ? "YES" : "NO",
            "-offscript.debugSeedSampleData",
            "NO",
            "-offscript.debugSeedLibrarySize",
            String(debugLibrarySize),
            "-offscript.debugSeedEpisodesPerShow",
            String(debugEpisodesPerShow),
            "-offscript.debugLaunchTab",
            String(debugLaunchTab)
        ]
        return app
    }
}

private extension XCUIElementQuery {
    func containing(labelContaining value: String) -> XCUIElement {
        matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }
}

private extension XCUIApplication {
    func screen(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }
}
