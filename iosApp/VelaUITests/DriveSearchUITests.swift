import XCTest

/// DRIVE-SEARCH: the driving chrome's own search field. The field is an overlay over the live
/// drive, not a sheet, so the banner, the camera and the Live Activity keep running. The test
/// proves the parser asks before replacing the destination, then searches along the route and
/// adds the first short result as a stop through the live session.
final class DriveSearchUITests: VelaUITestCase {
    /// A drive long enough that a slow CI search cannot reach the destination first: the host
    /// replay still drives Market Street, while the route continues across the bay.
    private let fixtureDrive = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.8044,-122.2712&travelmode=driving"

    override func tearDown() {
        if let app { endDrive(app) }
        super.tearDown()
    }

    func testSearchAndAddStopDuringDrive() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaOpenURL", fixtureDrive])
        let chooser = app.otherElements["route-sheet"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "the directions link did not open the chooser")
        if routeValue(app, "mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        let start = app.buttons["route-start"]
        XCTAssertTrue(waitUntil(180) { start.exists && start.isEnabled },
                      "no driving route: \(debugText("route-debug") ?? "none")")
        start.tap()
        XCTAssertTrue(waitUntil(20) { self.value(app, "nav") == "1" },
                      "navigation did not start")

        let open = app.buttons["drive-search-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20),
                      "the drive chrome has no search entry: \(debugText("nav-debug") ?? "none")")
        open.tap()
        let field = app.textFields["drive-search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the drive search field did not open")
        XCTAssertTrue(app.descendants(matching: .any)["drive-search"].exists, "the overlay is not identified")
        report("drive_search_open", "1")
        shot("drive-search")

        // Directions during a drive never replace the destination silently: the driver chooses.
        replaceText(app, field, "directions to coffee")
        XCTAssertTrue(app.descendants(matching: .any)["drive-search-choice"].waitForExistence(timeout: 5),
                      "directions did not ask add stop or replace: \(driveDebug(app) ?? "none")")
        XCTAssertTrue(app.buttons["drive-search-add-stop"].exists, "no add-stop choice")
        XCTAssertTrue(app.buttons["drive-search-replace"].exists, "no replace choice")
        app.buttons["drive-search-choice-cancel"].tap()
        XCTAssertTrue(waitUntil(5) { !app.descendants(matching: .any)["drive-search-choice"].exists },
                      "cancelling the choice left the prompt visible")
        report("drive_search_directions_choice", "1")

        // A command, not a bare phrase, so the parser's kind is proved on the same path the map
        // and the microphone use. The search is short: the drive is still running when it lands.
        replaceText(app, field, "search coffee")
        let results = app.buttons.matching(identifier: "drive-search-result")
        XCTAssertTrue(waitUntil(90) {
            let values = self.driveValues(app)
            return (values["cmd"] ?? "") == "search" && (Int(values["results"] ?? "") ?? 0) > 0
                && results.firstMatch.exists
        }, "the drive search kept no result: \(driveDebug(app) ?? "none")")
        let drive = driveValues(app)
        XCTAssertEqual(drive["nav"], "1", "the search ended the drive")
        report("drive_search_cmd", drive["cmd"] ?? "none")
        shot("drive-search-results")

        let before = navValues(app)
        let activityBefore = before["activity"] ?? "0"
        let stopBefore = Int(before["stopadds"] ?? "") ?? 0
        let sessionsBefore = before["sessions"] ?? "none"
        let stepBefore = Int(before["step"] ?? "") ?? 0

        results.firstMatch.tap()
        XCTAssertTrue(waitUntil(20) { !app.descendants(matching: .any)["drive-search"].exists },
                      "choosing a result left the overlay open")
        XCTAssertTrue(waitUntil(20) {
            (Int(self.navValues(app)["stopadds"] ?? "") ?? 0) > stopBefore
        }, "the result did not reach NavStore.addStop: \(debugText("nav-debug") ?? "none")")
        let after = navValues(app)
        XCTAssertEqual(after["nav"], "1", "adding a stop ended the drive")
        XCTAssertEqual(after["activity"], activityBefore, "adding a stop ended the Live Activity")
        XCTAssertEqual(after["sessions"], sessionsBefore, "the drive started a second session")
        XCTAssertGreaterThanOrEqual(Int(after["step"] ?? "") ?? 0, stepBefore,
                                    "adding a stop reset the step")
        XCTAssertTrue(app.otherElements["nav-banner"].exists, "the banner left after the stop")
        report("drive_search_added", "1")
        report("drive_search_session_starts", after["sessions"] ?? "none")
        shot("drive-search-stop")
    }

    /// Types into the drive field, replacing whatever a previous sentence left there. The field is
    /// not focused by the overlay, so the tap is the driver's own.
    private func replaceText(_ app: XCUIApplication, _ field: XCUIElement, _ text: String) {
        focus(field, app)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
        field.typeText(text)
        XCTAssertTrue(waitUntil(5) { (field.value as? String) == text },
                      "the drive field did not hold \(text): \(field.value ?? "empty")")
        field.typeText("\n")
    }

    private func focus(_ field: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { return }
            sleep(1)
        }
    }

    private func endDrive(_ app: XCUIApplication) {
        for _ in 0..<2 {
            let end = app.buttons["nav-end"]
            guard end.exists else {
                let done = app.buttons["nav-done"]
                if done.exists { done.tap() }
                return
            }
            end.tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
            if waitUntil(10, { !app.otherElements["nav-banner"].exists }) { return }
        }
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        navValues(app)[key]
    }

    private func navValues(_ app: XCUIApplication) -> [String: String] {
        values(app, id: "nav-debug")
    }

    private func driveValues(_ app: XCUIApplication) -> [String: String] {
        values(app, id: "drive-search-debug")
    }

    private func driveDebug(_ app: XCUIApplication) -> String? {
        debugText("drive-search-debug")
    }

    private func routeValue(_ app: XCUIApplication, _ key: String) -> String? {
        values(app, id: "route-debug")[key]
    }

    private func values(_ app: XCUIApplication, id: String) -> [String: String] {
        let line = app.staticTexts[id].exists ? app.staticTexts[id].label : ""
        var out: [String: String] = [:]
        for word in line.split(separator: " ") {
            let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }
}
