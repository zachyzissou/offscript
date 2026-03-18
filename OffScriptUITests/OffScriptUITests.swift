import XCTest

final class OffScriptUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingFirstScreenSmoke() throws {
        let app = makeApp(hasSeenOnboarding: false)
        app.launch()

        XCTAssertTrue(app.staticTexts["OffScript"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "Podcasts that feel curated").waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Skip for now"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testPostOnboardingShellSmoke() throws {
        let app = makeApp(hasSeenOnboarding: true)
        app.launch()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Queue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Search"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.staticTexts["Ready when you are"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["Your listening shelf"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Queue"].tap()
        XCTAssertTrue(app.staticTexts["Queue with intent"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["Find a signal worth following"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Ready when you are"].waitForExistence(timeout: 10))
    }

    private func makeApp(hasSeenOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offscript.hasSeenOnboarding",
            hasSeenOnboarding ? "YES" : "NO"
        ]
        return app
    }
}

private extension XCUIElementQuery {
    func containing(labelContaining value: String) -> XCUIElement {
        matching(NSPredicate(format: "label CONTAINS[c] %@", value)).firstMatch
    }
}
