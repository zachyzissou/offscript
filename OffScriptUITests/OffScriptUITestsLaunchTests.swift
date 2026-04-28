import XCTest

final class OffScriptUITestsLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchSmoke() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offscript.hasSeenOnboarding",
            "YES"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["HomeScreen"].waitForExistence(timeout: 10))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Shell Launch Smoke"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
