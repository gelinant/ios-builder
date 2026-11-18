import XCTest

/// TRANSIT-INTERP: the vehicles tab of the live panel. The fixture gives four in-service labels
/// from the captured Berlin `map/trips` reply, drawn at interpolated points; the scenario checks
/// that the count, the live-times count and the fact that every marker is labelled estimated all
/// reach the surface. The map symbol layer itself is not reachable from XCTest, so the screenshot
/// is the panel and the Kotlin tests own the geometry.
final class TransitVehiclesUITests: VelaUITestCase {
    func testInterpolatedVehicles() {
        // Same launch as the T-2 scenarios: the transit fixture hides the search field, so the
        // base `launch()` wait does not apply.
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitAdvancedFixture", "YES",
            "-VelaTransitVehicleFixture", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        let openTrip = app.buttons["transit-trip-open"]
        XCTAssertTrue(openTrip.waitForExistence(timeout: 20), "no trip-view button")
        openTrip.tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20), "no trip screen")
        XCTAssertTrue(waitUntil(10) { (self.value(app, "segments", id: "transit-trip-debug") ?? 0) > 0 },
                      "no segments")

        let live = app.buttons["transit-live-open"]
        XCTAssertTrue(live.waitForExistence(timeout: 20), "no live-map button")
        live.tap()
        XCTAssertTrue(app.buttons["transit-live-close"].waitForExistence(timeout: 20), "no live panel")
        app.buttons["transit-live-tab-vehicles"].tap()

        let toggle = app.switches["transit-vehicles-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no vehicles switch")
        if toggle.value as? String != "1" { toggle.tap() }
        XCTAssertTrue(waitUntil(10) {
            (self.intValue(app, "vehicles", id: "transit-vehicles-debug") ?? 0) > 0
        }, "no estimated vehicle on the fixture")

        let count = intValue(app, "vehicles", id: "transit-vehicles-debug") ?? 0
        let estimated = intValue(app, "estimated", id: "transit-vehicles-debug") ?? -1
        let liveTimes = intValue(app, "live_times", id: "transit-vehicles-debug") ?? -1
        report("vehicles_count", count)
        report("vehicles_estimated", estimated)
        report("vehicles_live_times", liveTimes)
        XCTAssertGreaterThanOrEqual(count, 3, "the fixture carries four in-service labels")
        XCTAssertEqual(estimated, 1, "every vehicle must be marked estimated")
        XCTAssertEqual(liveTimes, count, "every marker is built from a live time")

        // The estimate is words on the card, not a color or a live dot.
        let caption = app.staticTexts["transit-vehicles-caption"]
        XCTAssertTrue(caption.exists, "no estimated caption")
        XCTAssertTrue(caption.label.contains("not a measured position"), "the caption overclaims")
        let rows = app.descendants(matching: .any).matching(identifier: "transit-vehicle")
        XCTAssertEqual(rows.count, count, "one row per estimated vehicle")
        for index in 0..<rows.count {
            let label = rows.element(boundBy: index).label
            XCTAssertTrue(label.contains("estimated from live times, not GPS"), "row overclaims: \(label)")
            XCTAssertTrue(label.contains("next stop"), "row lacks its next stop: \(label)")
        }
        shot("transit-vehicles")
    }

    private func value(_ app: XCUIApplication, _ key: String, id: String) -> Int? {
        guard let line = line(app, id) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return Int(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ app: XCUIApplication, _ key: String, id: String) -> Int? {
        value(app, key, id: id)
    }

    private func line(_ app: XCUIApplication, _ id: String) -> String? {
        let element = app.staticTexts[id]
        return element.exists ? element.label : nil
    }
}
