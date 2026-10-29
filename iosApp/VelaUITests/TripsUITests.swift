import XCTest

/// DG-1 end to end: opt in, record the shared Market Street drive, end it, open the saved trip and
/// its speed profile, then export and diagnostics reach their screens. Screenshots: trips-list.png,
/// trip-detail.png and diagnostics.png.
final class TripsUITests: VelaUITestCase {
    func testRecordDriveAndOpenTrip() throws {
        let app = launch(camera: "sf", followUser: true)

        // Opt in from the trips sheet. The switch is off by default.
        app.buttons["trips-open"].tap()
        let toggle = app.switches["trips-recording-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no recording switch")
        func recordingOn() -> Bool { (debugText("trips-debug") ?? "").contains("recording=1") }
        if !recordingOn() {
            // A List row can swallow the tap; land on the switch itself.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            if !waitUntil(3, recordingOn) {
                toggle.tap()
            }
        }
        XCTAssertTrue(waitUntil(5, recordingOn), "trip recording did not turn on: \(debugText("trips-debug") ?? "no debug")")
        app.buttons["trips-done"].tap()

        // A coffee stop on the Market Street fixture, then Start as in NavUITests.
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(90) { self.routeValue("loading") == "0" && (Int(self.routeValue("routes") ?? "") ?? 0) > 0 },
                      "no driving route")
        app.buttons["route-start"].tap()
        XCTAssertTrue(waitUntil(15) { self.navValue("nav") == "1" }, "navigation did not start")

        // ci-ipa.sh arms sf-market when nav starts. Let five fixes land so the trip is kept.
        let before = navInt("left") ?? 0
        XCTAssertTrue(waitUntil(25) { (self.navInt("left") ?? before) < before }, "no movement")
        sleep(9)

        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.navValue("nav") == "0" })

        // The trip is now in the list, named after the destination and dated locally.
        app.buttons["trips-open"].tap()
        let tripRow = element("trip-row")
        XCTAssertTrue(tripRow.waitForExistence(timeout: 15), "no recorded trip in the list")
        XCTAssertFalse(app.staticTexts["trips-empty"].exists)
        shot("trips-list")

        tripRow.tap()
        let label = app.staticTexts["trip-detail-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 10), "trip detail did not open")
        let profile = element("trip-speed-profile")
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "no speed profile")
        let fixes = element("trip-fixes")
        XCTAssertTrue(fixes.waitForExistence(timeout: 5), "no fix count")
        report("trip_fixes", fixes.label)
        XCTAssertTrue(element("trip-share-gpx").exists, "no GPX share button")
        XCTAssertTrue(element("trip-trim-summary").exists, "no trim preview")
        sleep(5) // let the static map style and the line finish drawing
        shot("trip-detail")

        // Diagnostics is reachable from the same sheet and exports plain text.
        app.navigationBars.buttons["Trips"].tap()
        app.buttons["trips-diagnostics"].tap()
        let diagnostics = app.staticTexts["diagnostics-text"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10), "no diagnostics text")
        XCTAssertTrue(diagnostics.label.contains("Vela diagnostics"))
        XCTAssertTrue(diagnostics.label.contains("calibration "))
        XCTAssertTrue(diagnostics.label.contains("nav sessions "))
        report("diagnostics_lines", diagnostics.label.split(separator: "\n").count)
        shot("diagnostics")
        app.buttons["diagnostics-done"].tap()

        // Leave the simulator clean for the next run.
        let row = element("trip-row")
        if row.exists {
            row.swipeLeft()
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 5) { delete.tap() }
        }
        report("trips_flow", "recorded_opened_exportable")
    }

    /// TRIP-TRACE end to end: record a guided drive, open its full trace on the detail map, then
    /// play the same trace as a labelled demo replay and prove the puck moved. Screenshots:
    /// trip-trace-map.png and trip-demo-replay.png.
    func testFullTraceAndDemoMode() throws {
        let app = launch(camera: "sf", followUser: true)

        app.buttons["trips-open"].tap()
        let toggle = app.switches["trips-recording-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no recording switch")
        func recordingOn() -> Bool { (debugText("trips-debug") ?? "").contains("recording=1") }
        if !recordingOn() {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            if !waitUntil(3, recordingOn) { toggle.tap() }
        }
        XCTAssertTrue(waitUntil(5, recordingOn), "trip recording did not turn on")
        let folderNote = app.staticTexts["trips-trace-folder-note"]
        XCTAssertTrue(folderNote.waitForExistence(timeout: 5), "no folder section")
        XCTAssertTrue(folderNote.label.contains("iOS"), "the folder limits are not stated")
        XCTAssertTrue(app.buttons["trips-trace-folder-choose"].exists, "no folder picker")
        app.buttons["trips-done"].tap()

        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if routeValue("mode") != "DRIVE" { app.buttons["route-mode-DRIVE"].tap() }
        XCTAssertTrue(waitUntil(90) {
            self.routeValue("loading") == "0" && (Int(self.routeValue("routes") ?? "") ?? 0) > 0
        }, "no driving route")
        app.buttons["route-start"].tap()
        XCTAssertTrue(waitUntil(15) { self.navValue("nav") == "1" }, "navigation did not start")

        let before = navInt("left") ?? 0
        XCTAssertTrue(waitUntil(25) { (self.navInt("left") ?? before) < before }, "no movement")
        sleep(9)
        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.navValue("nav") == "0" })

        // The full trace opens on the detail map, which is the point of recording it.
        app.buttons["trips-open"].tap()
        let row = element("trip-row")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no recorded trip")
        row.tap()
        XCTAssertTrue(element("trip-detail-map").waitForExistence(timeout: 10), "no trace map")
        XCTAssertTrue(app.buttons["trip-save-full"].exists, "no full-trace save")
        sleep(6)
        shot("trip-trace-map")

        // The demo replay is its own labelled screen; nothing here is live guidance.
        app.buttons["trip-replay"].tap()
        let banner = app.staticTexts["demo-replay-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "no demo banner")
        let notice = app.staticTexts["demo-replay-notice"]
        XCTAssertTrue(notice.exists, "no replay notice")
        XCTAssertTrue(notice.label.contains("Not live guidance"))
        let start = debugText("demo-replay-debug") ?? ""
        XCTAssertTrue(waitUntil(10) {
            let now = self.debugText("demo-replay-debug") ?? ""
            return !now.isEmpty && now != start
        }, "the replay puck never moved")
        sleep(2)
        shot("trip-demo-replay")
        app.buttons["demo-replay-close"].tap()
        XCTAssertTrue(app.buttons["trip-replay"].waitForExistence(timeout: 5), "replay did not close")
        app.navigationBars.buttons["Trips"].tap()

        let again = element("trip-row")
        if again.exists {
            again.swipeLeft()
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 5) { delete.tap() }
        }
        report("trips_flow", "full_trace_map_demo_replay")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func navValue(_ key: String) -> String? {
        guard let line = debugText("nav-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func navInt(_ key: String) -> Int? {
        navValue(key).flatMap(Int.init)
    }
}
