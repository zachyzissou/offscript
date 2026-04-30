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
    func testSettingsPanelOpensWithLargeLibrarySeed() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 258, debugEpisodesPerShow: 3)
        app.launch()

        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 12))
        app.buttons["Open settings"].tap()

        let settingsLabel = app.staticTexts["SETTINGS · CONFIG PANEL"]
        XCTAssertTrue(settingsLabel.waitForExistence(timeout: 12), "Settings panel did not appear. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "258").waitForExistence(timeout: 12), "Settings counts did not reflect seeded library. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["NOT CONFIG"].waitForExistence(timeout: 8), "Simulator Settings should report missing iCloud entitlements without crashing. Hierarchy:\n\(app.debugDescription)")
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

    @MainActor
    func testTunerDetailScreensUseInlineBackChrome() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 4, debugEpisodesPerShow: 2, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 8))

        for _ in 0..<3 where !app.staticTexts["A Channel 001"].exists {
            app.swipeUp()
        }
        tapWhenReady(app.staticTexts["A Channel 001"], in: app, name: "A Channel 001 row")
        XCTAssertTrue(app.screen("PodcastDetailScreen").waitForExistence(timeout: 10), "Podcast detail did not open. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["PodcastDetailBackButton"].waitForExistence(timeout: 5), "Podcast detail inline back control missing. Hierarchy:\n\(app.debugDescription)")
        XCTAssertFalse(app.navigationBars.buttons["Library"].exists, "Podcast detail exposed native Library back chrome. Hierarchy:\n\(app.debugDescription)")

        tapWhenReady(app.staticTexts["A Channel 001 Episode 1"], in: app, name: "A Channel 001 Episode 1", maxSwipes: 6)
        XCTAssertTrue(app.screen("EpisodeDetailScreen").waitForExistence(timeout: 10), "Episode detail did not open. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["EpisodeDetailBackButton"].waitForExistence(timeout: 5), "Episode detail inline back control missing. Hierarchy:\n\(app.debugDescription)")
        XCTAssertFalse(app.navigationBars.buttons["Back"].exists, "Episode detail exposed native Back chrome. Hierarchy:\n\(app.debugDescription)")

        app.buttons["EpisodeDetailBackButton"].tap()
        XCTAssertTrue(app.screen("PodcastDetailScreen").waitForExistence(timeout: 8), "Episode back did not return to podcast detail. Hierarchy:\n\(app.debugDescription)")

        app.buttons["PodcastDetailBackButton"].tap()
        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 8), "Podcast back did not return to library. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLibraryReloadsAfterDetailUnsubscribe() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 4, debugEpisodesPerShow: 2, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["4 VISIBLE"].waitForExistence(timeout: 8))
        tapAfterScrolling(app.staticTexts["A Channel 001"], in: app, name: "A Channel 001 row", direction: .up)
        XCTAssertTrue(app.screen("PodcastDetailScreen").waitForExistence(timeout: 10), "Podcast detail did not open. Hierarchy:\n\(app.debugDescription)")

        tapWhenReady(app.buttons["PodcastDetailUnsubscribeButton"], in: app, name: "detail unsubscribe button", maxSwipes: 2)
        tapWhenReady(app.buttons["PodcastDetailConfirmUnsubscribeButton"], in: app, name: "confirm unsubscribe button", maxSwipes: 1)

        app.buttons["PodcastDetailBackButton"].tap()
        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 8), "Podcast back did not return to library. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["3 VISIBLE"].waitForExistence(timeout: 8), "Library did not refresh its directory count after unsubscribe. Hierarchy:\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["A Channel 001"].exists, "Unsubscribed show remained visible in the Library directory. Hierarchy:\n\(app.debugDescription)")
    }

    private enum ScrollDirection {
        case up
        case down
    }

    private func tapAfterScrolling(
        _ element: XCUIElement,
        in app: XCUIApplication,
        name: String,
        direction: ScrollDirection,
        maxSwipes: Int = 6,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maxSwipes where !element.exists || !element.isHittable {
            switch direction {
            case .up:
                app.swipeUp()
            case .down:
                app.swipeDown()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 4), "\(name) did not appear. Hierarchy:\n\(app.debugDescription)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) was not hittable. Hierarchy:\n\(app.debugDescription)", file: file, line: line)
        element.tap()
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
