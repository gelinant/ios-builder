import XCTest

/// A-1: aircraft around the view from a captured adsb.lol answer. The scenario proves the layer
/// installs, draws its nearest aircraft, opens the identification and altitude card and reports
/// that the fixture is not live traffic.
final class AviationLayerUITests: VelaUITestCase {
    func testAircraftAroundView() {
        let app = launch(
            camera: "37.6200,-122.3900,13",
            arguments: ["-VelaResetSettings", "YES", "-VelaAviationFixture", "YES"])

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()

        let row = app.buttons["world-layer-aviation"]
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.exists, "no World layers section")
        XCTAssertTrue(row.isEnabled, "A-1 must install the aviation row")
        XCTAssertEqual(row.value as? String, "off", "every world layer starts off")
        row.tap()
        XCTAssertTrue(waitUntil(5) { app.buttons["world-layer-aviation"].value as? String == "on" },
                      "the aviation switch did not turn on")

        app.buttons["layers-close"].tap()
        pan(app)
        XCTAssertTrue(waitUntil(10) { app.buttons["layers-button"].isHittable }, "no map after the pan")
        shot("aviation")

        // The rows are the same aircraft that were drawn. One tap opens the detail card.
        app.buttons["layers-button"].tap()
        let aircraftRows = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "world-row-aircraft-"))
        let first = aircraftRows.firstMatch
        for _ in 0..<12 where !(first.exists && first.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 10), "no aircraft rows after the fixture")
        first.tap()

        let card = app.descendants(matching: .any)["aviation-detail-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "no aircraft detail card")
        let ident = app.staticTexts["aviation-detail-ident"]
        let altitude = app.staticTexts["aviation-detail-altitude"]
        XCTAssertTrue(ident.exists, "the card must name the aircraft")
        XCTAssertFalse(ident.label.isEmpty, "the identification is empty")
        XCTAssertTrue(altitude.exists, "the card must show the altitude")
        shot("aviation-detail")

        let debug = app.staticTexts["aviation-detail-debug"].label
        let count = intValue(debug, "aviation_count")
        let source = stringValue(debug, "aviation_source")
        let live = intValue(debug, "aviation_live")
        report("aviation_count", count)
        report("aviation_source", source)
        report("aviation_live", live)
        XCTAssertGreaterThan(count, 0, "the fixture drew no aircraft: \(debug)")
        XCTAssertEqual(source, "fixture", "the UI scenario must read the captured fixture")
        XCTAssertEqual(live, 0, "fixture data is never reported as live")
    }

    private func pan(_ app: XCUIApplication) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.58))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.58))
        start.press(forDuration: 0.2, thenDragTo: end)
    }

    private func intValue(_ line: String, _ key: String) -> Int {
        for token in line.split(separator: " ") where token.hasPrefix("\(key)=") {
            return Int(token.dropFirst(key.count + 1)) ?? -1
        }
        return -1
    }

    private func stringValue(_ line: String, _ key: String) -> String {
        for token in line.split(separator: " ") where token.hasPrefix("\(key)=") {
            return String(token.dropFirst(key.count + 1))
        }
        return ""
    }
}
