import XCTest

/// T2-REACH: the user-facing "Reachable in N minutes" screen. It runs on the recorded Ferry
/// Building `one-to-all` reply (`-VelaTransitReachFixture`), presented by the Debug seam
/// `-VelaTransitReachTest`, so no Transitous request is made. The scenario reads the list order,
/// publishes the hull through the existing overlay mailbox, and records both screenshots.
final class TransitReachUITests: VelaUITestCase {
    func testReachListAndHull() {
        let app = launch(
            camera: "sf",
            arguments: ["-VelaTransitReachTest", "YES", "-VelaTransitReachFixture", "YES"])
        let close = app.buttons["transit-reach-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 40), "no reachability screen")
        XCTAssertTrue(app.staticTexts["transit-reach-debug"].waitForExistence(timeout: 20),
                      "no reachability debug line")

        XCTAssertTrue(waitUntil(15) {
            (self.intValue(app, "reach_stops", id: "transit-reach-debug") ?? 0) > 0
        }, "the captured reply listed no stop: \(app.staticTexts["transit-reach-debug"].label)")

        let minutes = intValue(app, "reach_minutes", id: "transit-reach-debug") ?? 0
        let stops = intValue(app, "reach_stops", id: "transit-reach-debug") ?? 0
        let fixture = value(app, "reach_fixture", id: "transit-reach-debug") ?? "?"
        let state = value(app, "reach_state", id: "transit-reach-debug") ?? "?"
        XCTAssertEqual(minutes, 30, "the screen did not open on the 30-minute budget")
        XCTAssertEqual(fixture, "1", "the scenario did not run on its recorded reply")
        XCTAssertEqual(state, "ready", "the list is not in its ready state")

        // One row per reachable stop, sorted by travel time; the first captured row is 5 minutes.
        let rows = app.descendants(matching: .any).matching(identifier: "transit-reach-stop")
        XCTAssertEqual(rows.count, stops, "one row per stop")
        XCTAssertTrue(rows.element(boundBy: 0).label.contains("5 min"),
                      "the list is not sorted by travel time: \(rows.element(boundBy: 0).label)")
        XCTAssertTrue(app.descendants(matching: .any)["transit-reach-canvas"].exists,
                      "no hull preview")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'not an official isochrone'")).count > 0,
            "the screen does not say the hull is not an official isochrone")
        shot("transit-reach")

        report("reach_minutes", minutes)
        report("reach_stops", stops)

        let map = app.buttons["transit-reach-map"]
        XCTAssertTrue(map.exists && map.isEnabled, "the hull action is not available")
        map.tap()
        XCTAssertTrue(app.staticTexts["transit-reach-published"].waitForExistence(timeout: 10),
                      "the hull was not published")
        XCTAssertTrue(waitUntil(5) {
            (self.intValue(app, "reach_hull", id: "transit-reach-debug") ?? 0) == 1
        }, "the published hull is not recorded")
        let hull = intValue(app, "reach_hull", id: "transit-reach-debug") ?? 0
        report("reach_hull", hull)
        XCTAssertEqual(hull, 1, "the convex hull was not published")
        shot("transit-reach-hull")

        // A budget change is one more user action; the list follows the new budget.
        app.buttons["transit-reach-minutes-15"].tap()
        XCTAssertTrue(waitUntil(10) {
            (self.intValue(app, "reach_minutes", id: "transit-reach-debug") ?? 0) == 15
        }, "the budget did not change")
        XCTAssertTrue(waitUntil(10) {
            (self.intValue(app, "reach_stops", id: "transit-reach-debug") ?? 0) > 0
        }, "the 15-minute list is empty on the captured reply")

        close.tap()
    }

    private func value(_ app: XCUIApplication, _ key: String, id: String) -> String? {
        let element = app.staticTexts[id]
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ app: XCUIApplication, _ key: String, id: String) -> Int? {
        value(app, key, id: id).flatMap(Int.init)
    }
}
