import XCTest

/// X-3: the recorded Transitous K itinerary in San Francisco, its in-app Start state and the debug
/// next-leg hook. ActivityKit assertions run only when the host enables Live Activities.
final class TransitActivityTests: VelaUITestCase {
    func testFixtureStartsAdvancesAndEnds() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        XCTAssertTrue(waitUntil(10) { self.value(app, "leg") == "0" }, "preview did not start on its walk")
        XCTAssertEqual(value(app, "stops"), "-1")
        let checksActivity = value(app, "actenabled") == "1"
        if checksActivity {
            XCTAssertTrue(waitUntil(10) { self.value(app, "activity") == "1" }, "no transit Live Activity")
            XCTAssertGreaterThan(intValue(app, "actrequests") ?? 0, 0)
            XCTAssertEqual(value(app, "acterror"), "0")
            XCTAssertEqual(value(app, "background"), "1", "transit location was not armed")
        } else {
            report("transit_activity", "unsupported_or_disabled")
        }
        shot("transit-activity-start")
        report("transit_start_leg", value(app, "leg") ?? "?")

        app.buttons["transit-next"].tap()
        XCTAssertTrue(waitUntil(10) {
            self.value(app, "leg") == "1" && self.value(app, "stops") == "4"
        }, "next-leg hook did not select the ride: \(debug(app) ?? "none")")
        XCTAssertEqual(value(app, "delay"), "4", "the fixture's real delay was not preserved")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { (self.intValue(app, "actupdates") ?? 0) > 0 },
                          "the leg change did not update ActivityKit")
            report("transit_activity_updates", intValue(app, "actupdates") ?? 0)
        }
        shot("transit-activity-next")
        report("transit_next_leg", value(app, "leg") ?? "?")
        report("transit_stops_remaining", value(app, "stops") ?? "?")

        app.buttons["transit-end"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "active") == "0" }, "transit session did not end")
        XCTAssertFalse(app.otherElements["transit-card"].exists)
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 5), "browse chrome was not restored")
        XCTAssertEqual(value(app, "background"), "0", "background location survived End")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { self.value(app, "activity") == "0" }, "Live Activity survived End")
            XCTAssertGreaterThan(intValue(app, "actended") ?? 0, 0)
            report("transit_activity", "started_updated_ended")
        }
        report("transit_end", "restored")
    }

    private func debug(_ app: XCUIApplication) -> String? {
        let element = app.staticTexts["transit-debug"]
        return element.exists ? element.label : nil
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debug(app) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ app: XCUIApplication, _ key: String) -> Int? {
        value(app, key).flatMap(Int.init)
    }
}
