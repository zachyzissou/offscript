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
    func testSettingsPanelOpensFromLibrary() throws {
        // Settings has its own button in LibraryTunerHeader. Build 51 saw a
        // Settings crash specifically when opened from Library, so the
        // Library entry point gets its own smoke beyond the Home one above.
        let app = makeApp(hasSeenOnboarding: true, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))

        let openSettings = app.buttons["Open settings"].firstMatch
        XCTAssertTrue(openSettings.waitForExistence(timeout: 8), "Library Open settings button missing. Hierarchy:\n\(app.debugDescription)")
        for _ in 0..<4 where !openSettings.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(openSettings.isHittable, "Library Open settings button not hittable. Hierarchy:\n\(app.debugDescription)")
        openSettings.tap()

        let settingsLabel = app.staticTexts["SETTINGS · CONFIG PANEL"]
        XCTAssertTrue(settingsLabel.waitForExistence(timeout: 10), "Settings panel did not appear from Library. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Close settings"].waitForExistence(timeout: 5))

        app.buttons["Close settings"].tap()
        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 8), "Closing Settings did not return to Library. Hierarchy:\n\(app.debugDescription)")
    }

    @MainActor
    func testSettingsPanelDismissAndReopenCycleStaysStable() throws {
        // Build 51 reports were on the Settings sheet itself, but a recurring
        // class of SwiftUI sheet crashes shows up only after a present →
        // dismiss → re-present cycle (state-restoration races, double
        // dismiss). Run that cycle and assert the panel is still healthy.
        let app = makeApp(hasSeenOnboarding: true)
        app.launch()

        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 10))

        for cycle in 0..<3 {
            let openSettings = app.buttons["Open settings"].firstMatch
            XCTAssertTrue(openSettings.waitForExistence(timeout: 8), "Open settings missing on cycle \(cycle). Hierarchy:\n\(app.debugDescription)")
            openSettings.tap()

            let settingsLabel = app.staticTexts["SETTINGS · CONFIG PANEL"]
            XCTAssertTrue(settingsLabel.waitForExistence(timeout: 8), "Settings did not appear on cycle \(cycle). Hierarchy:\n\(app.debugDescription)")

            let closeSettings = app.buttons["Close settings"]
            XCTAssertTrue(closeSettings.waitForExistence(timeout: 5))
            closeSettings.tap()

            XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 8), "Home did not return on cycle \(cycle). Hierarchy:\n\(app.debugDescription)")
        }

        XCTAssertEqual(app.state, .runningForeground, "App was not running in the foreground after Settings reopen cycles — likely a crash in the Settings sheet lifecycle.")
    }

    @MainActor
    func testSettingsSignOutConfirmDismissesCleanly() throws {
        // The destructive sign-out confirmation panel renders inline inside
        // Settings. #114 calls out destructive dialogs as a known crash
        // surface; pin that the user can present the confirmation, cancel
        // it, and stay in Settings without the sheet collapsing or the
        // runner dropping.
        let app = makeApp(hasSeenOnboarding: true)
        app.launch()

        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 10))
        tapWhenReady(app.buttons["Open settings"].firstMatch, in: app, name: "Open settings key")

        XCTAssertTrue(app.staticTexts["SETTINGS · CONFIG PANEL"].waitForExistence(timeout: 10))

        // Sign-out toggle is rendered only when signed in. The simulator
        // launches signed-out by default, so this surface won't be present
        // — guard so the test still adds value when sign-in flows change
        // the default. When present, exercise it.
        let signOutToggle = app.buttons["Sign out of OffScript"].firstMatch
        if signOutToggle.waitForExistence(timeout: 4) {
            tapWhenReady(signOutToggle, in: app, name: "sign out toggle")

            XCTAssertTrue(app.staticTexts["CONFIRM · SIGN OUT"].waitForExistence(timeout: 6),
                          "Sign-out confirmation panel did not appear. Hierarchy:\n\(app.debugDescription)")
            tapWhenReady(app.buttons["Cancel sign out"].firstMatch, in: app, name: "Cancel sign out")

            XCTAssertFalse(app.staticTexts["CONFIRM · SIGN OUT"].exists,
                           "Sign-out confirmation should be dismissed after Cancel. Hierarchy:\n\(app.debugDescription)")
        }

        // Whether or not we exercised the sign-out branch, the Settings
        // sheet must still be alive and the runner must still be foreground.
        XCTAssertTrue(app.staticTexts["SETTINGS · CONFIG PANEL"].waitForExistence(timeout: 5),
                      "Settings panel disappeared after destructive-dialog probe. Hierarchy:\n\(app.debugDescription)")
        XCTAssertEqual(app.state, .runningForeground,
                       "App dropped to background — destructive dialog likely crashed. Hierarchy:\n\(app.debugDescription)")
    }

    @MainActor
    func testLibraryShowsEmptyStateOnFreshLaunch() throws {
        // #115 acceptance: Library empty/loading/error states must be
        // clear. Uses the debugWipeLibrary launch arg (#177) to guarantee
        // the simulator boots into an empty store regardless of prior
        // seeded test runs.
        let app = makeApp(hasSeenOnboarding: true, debugLaunchTab: 1, debugWipeLibrary: true)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))

        XCTAssertTrue(app.staticTexts["● NO CHANNELS TUNED"].waitForExistence(timeout: 6),
                      "Library empty-state eyebrow missing. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Your library is empty"].waitForExistence(timeout: 4),
                      "Library empty-state headline missing. Hierarchy:\n\(app.debugDescription)")
    }

    @MainActor
    func testQueueShowsEmptyStateOnFreshLaunch() throws {
        // #126 acceptance: Queue UI under empty/small/large states needs
        // pinned coverage. The empty state lives in QueueView.emptyState
        // and reads `● QUEUE EMPTY` + "Nothing queued yet" + an EXPLORE
        // SHOWS escape hatch. A user with no subscriptions on a fresh
        // install lands here, so it has to be readable and the EXPLORE
        // key has to route somewhere useful.
        let app = makeApp(hasSeenOnboarding: true, debugLaunchTab: 2)
        app.launch()

        XCTAssertTrue(app.screen("QueueScreen").waitForExistence(timeout: 12))

        XCTAssertTrue(app.staticTexts["● QUEUE EMPTY"].waitForExistence(timeout: 6),
                      "Queue empty-state eyebrow missing. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["Nothing queued yet"].waitForExistence(timeout: 4),
                      "Queue empty-state headline missing. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "EXPLORE SHOWS").waitForExistence(timeout: 4),
                      "Queue empty-state escape hatch missing. Hierarchy:\n\(app.debugDescription)")
    }

    @MainActor
    func testQueueClearAllRequiresConfirmation() throws {
        // #126 acceptance: large queue states need a non-destructive
        // path through bulk clear. Verifies the `× CLEAR ALL` key opens
        // the `● CONFIRM CLEAR` strip, CANCEL dismisses without
        // wiping, and `× CONFIRM` actually clears the queue.
        let app = makeApp(
            hasSeenOnboarding: true,
            debugLaunchTab: 2,
            debugSeedSampleData: true,
            debugSeedQueue: 5
        )
        app.launch()

        XCTAssertTrue(app.screen("QueueScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts.containing(labelContaining: "STACKED").waitForExistence(timeout: 6),
                      "Queue should report a non-zero stacked count after seed. Hierarchy:\n\(app.debugDescription)")

        let clearAll = app.buttons["QueueClearAll"].firstMatch
        tapWhenReady(clearAll, in: app, name: "× CLEAR ALL key")

        XCTAssertTrue(app.staticTexts["● CONFIRM CLEAR"].waitForExistence(timeout: 4),
                      "Confirm strip should appear after × CLEAR ALL. Hierarchy:\n\(app.debugDescription)")

        // Cancel — strip dismisses, queue intact.
        tapWhenReady(app.buttons["QueueClearAllCancel"].firstMatch, in: app, name: "Confirm CANCEL key")
        XCTAssertFalse(app.staticTexts["● CONFIRM CLEAR"].waitForExistence(timeout: 2),
                       "Confirm strip should dismiss after CANCEL. Hierarchy:\n\(app.debugDescription)")

        // Reopen + confirm — queue clears, empty state renders.
        tapWhenReady(app.buttons["QueueClearAll"].firstMatch, in: app, name: "× CLEAR ALL key (second tap)")
        XCTAssertTrue(app.staticTexts["● CONFIRM CLEAR"].waitForExistence(timeout: 4))
        tapWhenReady(app.buttons["QueueClearAllConfirm"].firstMatch, in: app, name: "× CONFIRM key")

        XCTAssertTrue(app.staticTexts["● QUEUE EMPTY"].waitForExistence(timeout: 6),
                      "Queue empty-state eyebrow should render after × CONFIRM. Hierarchy:\n\(app.debugDescription)")
    }

    @MainActor
    func testQueueRowOpensEpisodeDetail() throws {
        // #258 acceptance: tapping a Queue row's rank+artwork+title zone
        // should push the episode's detail screen, leaving the inline
        // → PLAY / × DROP keys still tappable on their own.
        let app = makeApp(
            hasSeenOnboarding: true,
            debugLaunchTab: 2,
            debugSeedSampleData: true,
            debugSeedQueue: 3
        )
        app.launch()

        XCTAssertTrue(app.screen("QueueScreen").waitForExistence(timeout: 12))

        let openLink = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open '")).firstMatch
        XCTAssertTrue(openLink.waitForExistence(timeout: 8),
                      "Queue row navigation link missing. Hierarchy:\n\(app.debugDescription)")
        tapWhenReady(openLink, in: app, name: "Queue row open link")

        XCTAssertTrue(app.screen("EpisodeDetailScreen").waitForExistence(timeout: 10),
                      "Tapping queue row should open EpisodeDetailScreen. Hierarchy:\n\(app.debugDescription)")
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
    func testLibraryImportKeyOpensImportSheet() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))

        tapWhenReady(app.buttons["Import podcasts"].firstMatch, in: app, name: "Library Import key")

        let importHeader = app.staticTexts["IMPORT · ADD CHANNELS"]
        XCTAssertTrue(importHeader.waitForExistence(timeout: 10), "Import sheet did not appear. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(app.buttons["Close import"].waitForExistence(timeout: 5))

        app.buttons["Close import"].tap()
        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 8), "Closing Import did not return to Library. Hierarchy:\n\(app.debugDescription)")
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
    func testLargeLibrarySwitchesFromLibraryToHomeQuickly() throws {
        let app = makeApp(hasSeenOnboarding: true, debugLibrarySize: 258, debugEpisodesPerShow: 3, debugLaunchTab: 1)
        app.launch()

        XCTAssertTrue(app.screen("LibraryScreen").waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["SHOWS · DIRECTORY"].waitForExistence(timeout: 8))

        app.buttons["Home"].tap()
        XCTAssertTrue(app.screen("HomeScreen").waitForExistence(timeout: 4), "Home did not become visible quickly after leaving a 258-show Library. Hierarchy:\n\(app.debugDescription)")
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
        debugLaunchTab: Int = 0,
        debugWipeLibrary: Bool = false,
        debugSeedSampleData: Bool = false,
        debugSeedQueue: Int = 0
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offscript.hasSeenOnboarding",
            hasSeenOnboarding ? "YES" : "NO",
            "-offscript.debugSeedSampleData",
            debugSeedSampleData ? "YES" : "NO",
            "-offscript.debugSeedLibrarySize",
            String(debugLibrarySize),
            "-offscript.debugSeedEpisodesPerShow",
            String(debugEpisodesPerShow),
            "-offscript.debugLaunchTab",
            String(debugLaunchTab),
            "-offscript.debugWipeLibrary",
            debugWipeLibrary ? "YES" : "NO",
            "-offscript.debugSeedQueue",
            String(debugSeedQueue)
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
