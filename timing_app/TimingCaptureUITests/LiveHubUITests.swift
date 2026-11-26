import XCTest

// Pairs with a live hub and records crossings, the way a timer would.
// Needs HUB_ADDRESS and HUB_CODE (a fresh pairing code), and an app with no
// pairing yet; bin/e2e sets all of that up.
final class LiveHubUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func env(_ key: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { throw XCTSkip("\(key) not set") }
        return value
    }

    private func press(_ keys: String) {
        for key in keys { app.buttons[String(key)].tap() }
    }

    private func enter() { app.buttons["Enter"].tap() }

    private func waitForPill(_ label: String, timeout: TimeInterval = 30) {
        let pill = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: timeout), "sync pill never showed \(label)")
    }

    func testPairAndCapture() throws {
        let address = try env("HUB_ADDRESS")
        let code = try env("HUB_CODE")
        app.launch()
        let field = app.textFields["hub-address"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(address)
        app.textFields["pairing-code"].tap()
        app.textFields["pairing-code"].typeText(code)
        app.textFields["phone-name"].tap()
        app.textFields["phone-name"].typeText("Simulator")
        app.buttons["pair"].tap()

        XCTAssertTrue(app.buttons["Enter"].waitForExistence(timeout: 15), "never reached the capture screen")
        waitForPill("Synced")
        press("101")
        enter()
        waitForPill("Synced")
        XCTAssertTrue(app.staticTexts["101"].waitForExistence(timeout: 5))
        attach("after-capture")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
