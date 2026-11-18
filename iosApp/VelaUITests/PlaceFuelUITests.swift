import XCTest

/// PLC-FUEL on the simulator: the pump line and its nearby comparison, then the closing
/// countdown. Both places are fixtures opened without a search or a Google request, so the
/// scenario stays deterministic on the CI runner's datacenter address.
final class PlaceFuelUITests: VelaUITestCase {
    func testFuelPlaceCard() throws {
        let app = launch(camera: "sf", arguments: ["-VelaPlaceFuelFixture", "fuel"])
        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30), "no fuel place sheet")
        XCTAssertEqual(name.label, "Vela Fuel Test")

        let fuel = app.descendants(matching: .any)["place-fuel"]
        XCTAssertTrue(fuel.waitForExistence(timeout: 10), "no fuel line")
        XCTAssertTrue(fuel.label.contains("172.9p/E10 · 199.9p/B7"), "wrong pump price: \(fuel.label)")
        XCTAssertTrue(fuel.label.contains("ESSO"), "no forecourt brand: \(fuel.label)")
        XCTAssertTrue(fuel.label.contains("Updated"), "no report age: \(fuel.label)")
        let nearby = app.descendants(matching: .any)["place-fuel-nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 5), "no cheap nearby comparison")
        XCTAssertTrue(nearby.label.contains("169.9p/E10"), "wrong nearby price: \(nearby.label)")
        XCTAssertTrue(nearby.label.contains("TESCO"), "wrong nearby brand: \(nearby.label)")
        report("place_fuel", fuel.label)
        report("place_fuel_nearby", nearby.label)
        shot("place-fuel")
    }

    func testClosingTimeCard() throws {
        let app = launch(camera: "sf", arguments: ["-VelaPlaceFuelFixture", "closing"])
        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30), "no closing place sheet")
        XCTAssertEqual(name.label, "Vela Closing Test")

        let closing = app.descendants(matching: .any)["place-closing"]
        XCTAssertTrue(closing.waitForExistence(timeout: 10), "no closing countdown")
        XCTAssertTrue(closing.label.hasPrefix("Closes in "), "wrong closing line: \(closing.label)")
        XCTAssertTrue(closing.label.hasSuffix(" min"), "wrong closing line: \(closing.label)")
        report("place_closing", closing.label)
        shot("place-closing")
    }

    func testClosingCountdownAcrossMidnight() throws {
        // Pin the app's clock at 23:50 local while the fixture closes at 12:45 AM: the countdown
        // must wrap to the coming day and read 55 minutes, day or night on the runner.
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = 23
        parts.minute = 50
        parts.second = 0
        guard let pinned = Calendar.current.date(from: parts) else {
            XCTFail("cannot build the pinned 23:50 instant")
            return
        }
        let app = launch(camera: "sf", arguments: [
            "-VelaPlaceFuelFixture", "midnight",
            "-VelaClosingNowEpoch", String(Int(pinned.timeIntervalSince1970)),
        ])
        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30), "no midnight place sheet")
        XCTAssertEqual(name.label, "Vela Midnight Closing Test")

        let closing = app.descendants(matching: .any)["place-closing"]
        XCTAssertTrue(closing.waitForExistence(timeout: 10), "no closing countdown after midnight")
        XCTAssertTrue(closing.label.hasPrefix("Closes in "), "wrong closing line: \(closing.label)")
        XCTAssertTrue(closing.label.contains("55"), "wrong closing line: \(closing.label)")
        report("closing_minutes", 55)
        shot("place-closing-midnight")
    }
}
