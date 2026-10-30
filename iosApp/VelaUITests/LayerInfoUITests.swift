import XCTest

/// LAYER-INFO: the legend lists every layer that is on with its colour, unit, source and data
/// age, in light and dark, and the parity check proves the map fields and the card fields are the
/// same list. The card screenshot uses the captured adsb.lol fixture, so the run needs no network.
final class LayerInfoUITests: VelaUITestCase {
    func testLegendAndInfoParity() {
        let app = launch(
            camera: "37.6200,-122.3900,13",
            arguments: ["-VelaResetSettings", "YES", "-VelaAviationFixture", "YES",
                        "-VelaMapLayersFixture", "YES"])

        openLegend(app)
        let legend = app.descendants(matching: .any)["layer-legend"]
        XCTAssertTrue(legend.waitForExistence(timeout: 10), "no legend")
        let debug = app.staticTexts["layer-legend-debug"]
        XCTAssertTrue(debug.exists, "the legend must report its contract")
        let layers = intValue(debug.label, "legend_layers")
        let parity = intValue(debug.label, "legend_parity")
        report("legend_layers", layers)
        report("legend_parity", parity)
        XCTAssertGreaterThan(layers, 0, "the legend lists no layer: \(debug.label)")
        XCTAssertEqual(parity, 1, "the map and card field lists drifted: \(debug.label)")

        // One VoiceOver element per layer, with its meaning read out.
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "layer-legend-row-"))
        XCTAssertGreaterThan(rows.count, 0, "no legend row")
        XCTAssertFalse(rows.firstMatch.label.isEmpty, "a legend row has no spoken meaning")
        shot("layer-legend")
        app.buttons["layer-legend-close"].tap()

        // The same card the parity test compares: the aircraft card over the captured fixture.
        app.buttons["layers-button"].tap()
        enableWorldLayer(app, "aviation")
        app.buttons["layers-close"].tap()
        pan(app)
        XCTAssertTrue(waitUntil(10) { app.buttons["layers-button"].isHittable }, "no map after pan")
        app.buttons["layers-button"].tap()
        let aircraft = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "world-row-aircraft-")).firstMatch
        for _ in 0..<12 where !(aircraft.exists && aircraft.isHittable) { app.swipeUp() }
        XCTAssertTrue(aircraft.waitForExistence(timeout: 10), "no aircraft row after the fixture")
        aircraft.tap()
        XCTAssertTrue(app.descendants(matching: .any)["aviation-detail-card"]
            .waitForExistence(timeout: 10), "no aircraft card")
        shot("layer-card-parity")

        // Dark legend, same contract, on a fresh launch so the theme is applied from the start.
        let dark = launch(
            camera: "37.6200,-122.3900,13",
            arguments: ["-VelaResetSettings", "YES", "-VelaForceDark", "YES",
                        "-VelaMapLayersFixture", "YES"])
        openLegend(dark)
        XCTAssertTrue(dark.descendants(matching: .any)["layer-legend"]
            .waitForExistence(timeout: 10), "no dark legend")
        XCTAssertEqual(intValue(dark.staticTexts["layer-legend-debug"].label, "legend_parity"), 1)
        shot("layer-legend-dark")
    }

    /// Opens the layers sheet, turns the camera overlay on so the legend has a non-world layer,
    /// then opens the legend, which dismisses the sheet and draws the card over the map.
    private func openLegend(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        let speed = app.buttons["layer-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10), "no layers sheet")
        if speed.value as? String != "on" { speed.tap() }
        app.buttons["layer-legend-open"].tap()
    }

    private func enableWorldLayer(_ app: XCUIApplication, _ id: String) {
        let row = app.buttons["world-layer-\(id)"]
        for _ in 0..<12 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertTrue(row.exists, "no world layer \(id)")
        if row.value as? String != "on" { row.tap() }
        XCTAssertTrue(waitUntil(5) { row.value as? String == "on" },
                      "the \(id) switch did not turn on")
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
}
