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

    private func press(_ keys: String, in scope: XCUIElement? = nil) {
        for key in keys { (scope ?? app).buttons[String(key)].firstMatch.tap() }
    }

    private func enter() { app.buttons["Enter"].tap() }

    private func waitForPill(_ label: String, timeout: TimeInterval = 30) {
        let pill = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: timeout), "sync pill never showed \(label)")
    }

    // Pairs on the first test of a run; later tests find the phone already paired.
    private func launchPaired() throws {
        let address = try env("HUB_ADDRESS")
        app.launch()
        if app.buttons["Enter"].waitForExistence(timeout: 3) { return }
        let code = try env("HUB_CODE")
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
    }

    func testPairAndCapture() throws {
        try launchPaired()
        waitForPill("Synced")
        press("101")
        enter()
        waitForPill("Synced")
        let bib = app.descendants(matching: .any).matching(identifier: "crossing").firstMatch.buttons["Edit bib"]
        XCTAssertTrue(bib.waitForExistence(timeout: 5))
        XCTAssertEqual(bib.value as? String, "101")
        attach("after-capture")
    }

    // A no-bib crossing, corrected to a roster bib; an unknown bib; a delete; the filter.
    func testCorrectDeleteFilter() throws {
        let rosterBib = try env("HUB_BIB")
        let rosterName = try env("HUB_NAME")
        try launchPaired()
        waitForPill("Synced")
        let firstRow = app.descendants(matching: .any).matching(identifier: "crossing").firstMatch

        enter() // no bib
        XCTAssertTrue(app.staticTexts["No bib"].waitForExistence(timeout: 5))
        firstRow.buttons["Edit bib"].tap()
        let sheet = app.descendants(matching: .any).matching(identifier: "bib-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        press(rosterBib, in: sheet)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", rosterName)).firstMatch.waitForExistence(timeout: 5))
        sheet.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[rosterName].waitForExistence(timeout: 10), "corrected row doesn't show the racer")
        XCTAssertTrue(app.staticTexts["entered: no bib"].exists)
        waitForPill("Synced")

        press("99999")
        enter()
        XCTAssertTrue(app.staticTexts["Unknown bib"].waitForExistence(timeout: 5))
        attach("unknown-bib")
        firstRow.buttons["Delete crossing"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Unknown bib"].waitForNonExistence(timeout: 5))
        waitForPill("Synced")

        firstRow.buttons["Show only this bib"].tap()
        XCTAssertTrue(app.buttons["Show all bibs"].waitForExistence(timeout: 5))
        attach("filtered")
        app.buttons["Show all bibs"].tap()
        XCTAssertFalse(app.buttons["Show all bibs"].exists)
    }

    // Course events: the volunteer picks where the phone is. (Pair with a course event: EVENT=<id>.)
    func testLocationPick() throws {
        try launchPaired()
        let chip = app.buttons["location"]
        XCTAssertTrue(chip.waitForExistence(timeout: 30), "no location chip (not a course event?)")
        XCTAssertEqual(chip.label, "Finish")
        chip.tap()
        app.buttons["Aid 1"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'location' AND label == 'Aid 1'")).firstMatch.waitForExistence(timeout: 5))
        waitForPill("Synced")
    }

    // An official moved the phone to Aid 2 on the hub; the phone follows within a roster refresh.
    func testLocationAdoptsHubMove() throws {
        try launchPaired()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier == 'location' AND label == 'Aid 2'")).firstMatch.waitForExistence(timeout: 90))
        attach("moved-by-hub")
    }

    func testExportAndUnpair() throws {
        try launchPaired()
        waitForPill("Synced")
        app.buttons["Menu"].tap()
        app.buttons["Export log"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "no share sheet")
        attach("export")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(share.waitForNonExistence(timeout: 5))
        app.buttons["Menu"].tap()
        app.buttons["Unpair"].tap()
        XCTAssertTrue(app.textFields["hub-address"].waitForExistence(timeout: 5), "unpair didn't return to the pair screen")
    }

    // The spec's offline check, in steps run with the hub stopped and started between them
    // (see README, "End-to-end check").

    // Hub stopped: three crossings, one correction and one delete wait on the phone.
    func testOfflineRecord() throws {
        try launchPaired()
        let firstRow = app.descendants(matching: .any).matching(identifier: "crossing").firstMatch
        enter() // a no-bib crossing
        press("7001")
        enter()
        press("7002")
        enter()
        firstRow.buttons["Edit bib"].tap() // 7002 → 7003
        let sheet = app.descendants(matching: .any).matching(identifier: "bib-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        press("7003", in: sheet)
        sheet.buttons["Save"].tap()
        let second = app.descendants(matching: .any).matching(identifier: "crossing").element(boundBy: 1)
        second.buttons["Delete crossing"].tap() // 7001
        app.buttons["Delete"].tap()
        waitForPill("Offline · 5 to send")
        attach("offline")

        app.buttons["Menu"].tap()
        app.buttons["Pair again"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '5 crossings on this phone'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pair"].isEnabled)
        attach("re-pair-warning")
        app.buttons["Back to capture"].tap()
        XCTAssertTrue(app.buttons["Enter"].waitForExistence(timeout: 5))
    }

    // Hub back: everything goes.
    func testBackOnline() throws {
        try launchPaired()
        waitForPill("Synced", timeout: 60)
        XCTAssertTrue(app.staticTexts["No bib"].exists)
    }

    // A chief resolved the no-bib crossing on the console (HUB_RESOLVED_BIB); the phone shows it, locked.
    func testResolvedBibShows() throws {
        let resolved = try env("HUB_RESOLVED_BIB")
        try launchPaired()
        let row = app.descendants(matching: .any).matching(identifier: "crossing")
            .containing(NSPredicate(format: "label == 'entered: no bib'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "the resolved crossing never showed")
        XCTAssertEqual(row.buttons["Edit bib"].value as? String, resolved)
        XCTAssertFalse(row.buttons["Edit bib"].isEnabled, "an official's ruling should lock the bib")
        attach("resolved")
    }

    // Digits from a hardware keyboard reach the bib. (Return and Delete aren't checked:
    // XCUITest's synthesized Return/Delete never reach the app, so check those by hand.)
    func testHardwareKeyboard() throws {
        try launchPaired()
        waitForPill("Synced")
        for key in "8889" { app.typeKey(String(key), modifierFlags: []) }
        XCTAssertEqual(app.staticTexts["bib-display"].label, "8889", "typed digits didn't reach the bib")
        for _ in 0..<4 { app.buttons["Backspace"].tap() }
    }

    // Screenshots in every orientation (run on an iPhone and an iPad simulator).
    func testLayouts() throws {
        try launchPaired()
        waitForPill("Synced")
        for (name, orientation) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft), ("landscape-right", .landscapeRight)] {
            XCUIDevice.shared.orientation = orientation
            sleep(1)
            XCTAssertTrue(app.buttons["Enter"].isHittable, "Enter not reachable in \(name)")
            attach(name)
            if name == "landscape" {
                app.descendants(matching: .any).matching(identifier: "crossing").firstMatch.buttons["Edit bib"].tap()
                sleep(1)
                attach("landscape-bib-sheet")
                app.buttons["Cancel"].tap()
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
