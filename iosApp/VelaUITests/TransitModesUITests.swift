import XCTest

/// TRANSIT-MODES: on a recorded two-leg trip (Paris, Hôtel de Ville to La Défense: walk, Metro 1,
/// transfer walk, RER A, final walk) the detail sheet names every leg's vehicle and keeps the whole
/// itinerary, transfer and waiting time included. The last assertion is the point of the test: the
/// final walk after the transfer must still be there, not only the first ride.
final class TransitModesUITests: VelaUITestCase {
    private func launchTransferFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitTransfer", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 30), "no transit card")
        return app
    }

    func testAllLegsAndModes() {
        let app = launchTransferFixture()

        let open = app.buttons["transit-detail-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no detail sheet control on the fixture card")
        open.tap()

        let sheet = app.descendants(matching: .any)["steps-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "no transit detail sheet")

        let debug = app.staticTexts["transit-modes-debug"]
        XCTAssertTrue(debug.waitForExistence(timeout: 20), "no modes debug line")
        let legs = intValue(debug.label, "legs") ?? -1
        let modes = value(debug.label, "modes") ?? "?"
        let transfers = intValue(debug.label, "transfers") ?? -1
        report("transit_legs", legs)
        report("transit_modes", modes)
        report("transit_transfer", transfers)

        // Every leg of the reply, in travel order, with the vehicle the planner named.
        XCTAssertEqual(legs, 5, "the sheet stopped before the end of the itinerary")
        XCTAssertEqual(modes, "walk,metro,walk,rail,walk", "a leg lost its mode")
        XCTAssertEqual(transfers, 1, "the transfer between the two rides is not shown")

        let labels = app.staticTexts.matching(identifier: "transit-detail-mode")
        XCTAssertEqual(labels.count, 5, "one mode headline per leg")
        let titles = (0..<labels.count).map { labels.element(boundBy: $0).label }
        XCTAssertEqual(titles, ["Walk", "M1", "Walk", "RER A", "Walk"],
                       "the legs are not the planner's order and modes: \(titles)")
        // The mode names are readable words, not only a line number.
        let modeNames = app.staticTexts.matching(identifier: "transit-detail-mode-name")
        XCTAssertGreaterThanOrEqual(modeNames.count, 5, "no readable mode name per leg")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Metro'")).count > 0,
                      "the subway leg does not say Metro")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Rail'")).count > 0,
                      "the RER leg does not say Rail")
        shot("transit-modes")

        // The transfer: its stop and the planner's waiting time between the two arrivals/departures.
        let transfer = app.descendants(matching: .any)["transit-detail-transfer"].firstMatch
        var tries = 0
        while !(transfer.exists && transfer.isHittable) && tries < 8 {
            sheet.swipeUp()
            tries += 1
        }
        XCTAssertTrue(transfer.exists, "no transfer row")
        XCTAssertTrue(transfer.label.contains("Transfer at Charles de Gaulle - Étoile"),
                      "the transfer point is missing: \(transfer.label)")
        XCTAssertTrue(transfer.label.contains("3 min wait"),
                      "the waiting time between arrival and departure is missing: \(transfer.label)")
        shot("transit-transfer")

        // The itinerary goes on after the transfer: the RER leg and the final walk are rendered.
        XCTAssertTrue(app.staticTexts["RER A"].exists, "the second ride is missing")
        let finalWalk = labels.element(boundBy: labels.count - 1)
        XCTAssertTrue(finalWalk.exists, "the final walk after the transfer is missing")

        report("transit_all_legs_and_modes", "ok")
        app.buttons["steps-close"].tap()
    }

    private func value(_ line: String, _ key: String) -> String? {
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ line: String, _ key: String) -> Int? {
        value(line, key).flatMap(Int.init)
    }
}
