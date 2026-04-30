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
    func testSettingsPanelOpensFromHome() throws {
        let app = makeApp(hasSeenOnboarding: true)
        app.launch()

        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 10))
        app.buttons["Open settings"].tap()

        let settingsLabel = app.staticTexts["SETTINGS · CONFIG PANEL"]
        if !settingsLabel.waitForExistence(timeout: 10) {
            XCTFail("Settings panel did not appear. Hierarchy:\n\(app.debugDescription)")
        }
        XCTAssertTrue(app.buttons["Close settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeLibrarySeedSmoke() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 258, debugEpisodesPerShow: 3, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "258").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testLargeLibraryAlphabetRailJumpsToSelectedLetter() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 258, debugEpisodesPerShow: 1, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 8))
        let carousel = app.scrollViews["LibraryAlphabetCarousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 8))
        for _ in 0..<4 where !carousel.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(carousel.isHittable)
        let zJump = carousel.descendants(matching: .any)["LibraryJumpLetterZ"]
        XCTAssertTrue(zJump.waitForExistence(timeout: 8))
        for _ in 0..<12 where !zJump.isHittable {
            carousel.swipeLeft()
        }
        XCTAssertTrue(zJump.isHittable, "Expected to reach LibraryJumpLetterZ within the alphabet carousel")

        zJump.tap()

        let zHeader = app.staticTexts["LibrarySectionHeaderZ"]
        if !zHeader.waitForExistence(timeout: 12) {
            zJump.tap()
        }
        XCTAssertTrue(zHeader.waitForExistence(timeout: 8), "Expected Z section after tapping alphabet rail. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Z Channel 026"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testLargeLibraryDirectoryControlsStayResponsive() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 258, debugEpisodesPerShow: 3, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 8))

        tapWhenReady(app.buttons["ATTN"].firstMatch, in: app, name: "ATTN sort")
        XCTAssertTrue(app.staticTexts["● 1 IN PROGRESS"].waitForExistence(timeout: 10))

        tapWhenReady(app.buttons["UNPLAYED"].firstMatch, in: app, name: "UNPLAYED scope")
        XCTAssertTrue(app.staticTexts["A Channel 001"].waitForExistence(timeout: 10))

        let filter = libraryFilterField(in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 8), "Library filter did not appear. Hierarchy:\n\(app.debugDescription)")
        filter.tap()
        filter.typeText("Z Channel")
        XCTAssertTrue(app.staticTexts["Z Channel 026"].waitForExistence(timeout: 10))

        let clearFilter = app.buttons["Clear library filter"].firstMatch
        XCTAssertTrue(clearFilter.waitForExistence(timeout: 5), "Clear library filter did not appear. Hierarchy:\n\(app.debugDescription)")
        clearFilter.tap()
        XCTAssertTrue(app.staticTexts["A Channel 001"].waitForExistence(timeout: 10))
    }

    private func tapWhenReady(
        _ element: XCUIElement,
        in app: XCUIApplication,
        name: String,
        maxSwipes: Int = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), "\(name) did not appear. Hierarchy:\n\(app.debugDescription)", file: file, line: line)
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeUp()
        }
        for _ in 0..<maxSwipes where !element.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable, "\(name) was not hittable. Hierarchy:\n\(app.debugDescription)", file: file, line: line)
        element.tap()
    }

    private func libraryFilterField(in app: XCUIApplication) -> XCUIElement {
        let labeledField = app.textFields["Filter shows"]
        if labeledField.exists {
            return labeledField
        }
        return app.textFields["FILTER SHOWS BY TITLE, AUTHOR, OR CATEGORY"]
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
