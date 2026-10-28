import XCTest

/// NAV-FREEDRIVE's second half: a stop added through the drive's own sheet, without ending the
/// drive, with the recalculation indicator and a refreshed per-stop ETA. The destination comes
/// from the shared-link fixture the banner scenarios already use; the stop comes from the app's
/// live search.
final class NavStopsUITests: VelaUITestCase {
    private let fixtureDrive = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving"

    override func tearDown() {
        if let app, app.buttons["nav-end"].exists {
            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testStopAddedDuringTheDriveRefreshesTheEta() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaOpenURL", fixtureDrive, "-VelaNavAlertsFixture", "YES"])
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "the directions link did not open the chooser")
        if value(in: "route-debug", key: "mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        let start = app.buttons["route-start"]
        XCTAssertTrue(waitUntil(120) { start.exists && start.isEnabled },
                      "no driving route: \(debugText("route-debug") ?? "none")")
        start.tap()
        XCTAssertTrue(waitUntil(20) { self.value("nav") == "1" }, "navigation did not start")
        XCTAssertEqual(value("stops"), "0", "the fixture drive already has a stop")
        XCTAssertFalse(app.descendants(matching: .any)["nav-stop-eta"].exists,
                       "a direct drive should not show a next-stop ETA")

        let addStop = app.buttons["nav-add-stop"]
        XCTAssertTrue(addStop.waitForExistence(timeout: 20), "no Add stop action in the drive chrome")
        addStop.tap()

        let field = app.textFields["nav-stop-search"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the add-stop sheet did not open")
        field.tap()
        field.typeText("Ferry Building\n")
        let result = app.buttons.matching(identifier: "nav-stop-result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 90),
                      "the stop search returned nothing: \(debugText("nav-voice-debug") ?? "none")")
        result.tap()

        XCTAssertTrue(waitUntil(10) { !field.exists }, "the add-stop sheet stayed open")
        XCTAssertTrue(waitUntil(30) { self.value("stopadds") == "1" },
                      "the stop never reached the session: \(debugText("nav-debug") ?? "none")")
        XCTAssertTrue(waitUntil(60) { self.value("recalc") == "0" },
                      "the recalculation state never cleared: \(debugText("nav-debug") ?? "none")")
        XCTAssertTrue(waitUntil(30) { self.value("stops") == "1" },
                      "the drive lost the new stop: \(debugText("nav-debug") ?? "none")")
        XCTAssertEqual(value("nav"), "1", "adding a stop ended the drive")
        XCTAssertEqual(value("sessions"), "1", "adding a stop started a second navigation session")
        XCTAssertTrue(app.staticTexts["nav-next-stop"].waitForExistence(timeout: 10),
                      "no next-stop line after the stop")
        XCTAssertTrue(app.staticTexts["nav-stop-eta"].exists, "the stop ETA did not appear")
        XCTAssertTrue(app.staticTexts["nav-stop-figures"].exists, "the stop figures did not appear")
        report("nav_stops_added", value("stopadds") ?? "?")
        report("nav_stops_eta", app.staticTexts["nav-stop-eta"].label)
        shot("nav-stop-added")
    }

    private func value(_ key: String) -> String? {
        value(in: "nav-debug", key: key)
    }

    private func value(in identifier: String, key: String) -> String? {
        guard let line = debugText(identifier) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
