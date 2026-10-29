import XCTest

/// T2-WIRE: the panels publish their already-fetched transit data to the map hub, and the map
/// draws it without owning a model or sending a request. The scenario runs on the recorded Berlin
/// lines and vehicles of `-VelaTransitAdvancedFixture` and `-VelaTransitVehicleFixture`; the
/// San Francisco trip fixture only supplies the card that opens the live panel. Every capture is
/// taken after the panel and the trip screen are closed, so the pixels prove the hub, not the sheet.
final class TransitMapUITests: VelaUITestCase {
    /// U2's second vertex in the recorded Berlin path. At z15 the map centre sits on the line.
    private let lineCentre = "52.52205,13.41376,15"
    /// U2's estimated vehicle in the same fixture, about 29 pt west and 17 pt north of the line
    /// vertex at z15. The vehicle symbol sits above the line, so this tap proves the dot wins.
    private let vehicleOffset = CGVector(dx: 0.427, dy: 0.480)

    func testLinesAndVehiclesOnTheMap() {
        let app = launch(
            camera: lineCentre,
            arguments: [
                "-VelaResetSettings", "YES",
                "-VelaTransitFixture", "YES",
                "-VelaTransitAdvancedFixture", "YES",
                "-VelaTransitVehicleFixture", "YES",
                // The recorded trip would fit San Francisco; this keeps the Berlin launch camera.
                "-VelaTransitMapCamera", lineCentre,
            ])
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 60),
                      "the transit fixture did not open its guidance card")

        // 1. The live lines: one explicit load in the panel, then both surfaces are closed.
        openTrip(app)
        openLive(app)
        app.buttons["transit-live-tab-lines"].tap()
        app.buttons["transit-live-lines-load"].tap()
        XCTAssertTrue(waitUntil(20) { (self.intValue(app, "lines", id: "transit-live-lines-debug") ?? 0) > 0 },
                      "the live panel loaded no line: \(debugText("transit-live-lines-debug") ?? "no line")")
        closeLive(app)
        closeTrip(app)

        XCTAssertTrue(waitForMapLines(app, atLeast: 1),
                      "the lines never reached the map: \(tapChain(app))")
        let drawnLines = mapCount(app, "transit_lines")
        report("map_transit_lines", drawnLines)
        XCTAssertGreaterThan(drawnLines, 0, "the map drew no transit line: \(tapChain(app))")
        sleep(3)
        shot("transit-map-lines")

        // 2. The estimated vehicles: the switch of the vehicles tab is the only source.
        openTrip(app)
        openLive(app)
        app.buttons["transit-live-tab-vehicles"].tap()
        let toggle = app.switches["transit-vehicles-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no vehicles switch")
        if toggle.value as? String != "1" { toggle.tap() }
        XCTAssertTrue(waitUntil(20) {
            (self.intValue(app, "vehicles", id: "transit-vehicles-debug") ?? 0) > 0
        }, "no estimated vehicle was reported")
        closeLive(app)
        closeTrip(app)

        XCTAssertTrue(waitForMapVehicles(app, atLeast: 1),
                      "the estimated vehicles never reached the map: \(tapChain(app))")
        let drawnVehicles = mapCount(app, "transit_vehicles")
        let estimated = mapCount(app, "transit_estimated")
        report("map_transit_vehicles", drawnVehicles)
        report("map_transit_estimated", estimated)
        XCTAssertGreaterThan(drawnVehicles, 0, "the map drew no vehicle: \(tapChain(app))")
        XCTAssertEqual(estimated, 1, "a map vehicle was not labelled estimated: \(tapChain(app))")
        sleep(3)
        shot("transit-map-vehicles")

        // A tap on a dot opens the same line sheet. The z-order makes the dot win over its line.
        tapCentre(app, offset: vehicleOffset)
        XCTAssertTrue(app.otherElements["transit-line-sheet"].waitForExistence(timeout: 20),
                      "a tap on a vehicle opened no line sheet: \(layersDebug(app))")
        XCTAssertTrue(app.descendants(matching: .any)["transit-line-badge"].waitForExistence(timeout: 10),
                      "the vehicle's line sheet has no badge")
        app.buttons["transit-line-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.otherElements["transit-line-sheet"].exists },
                      "the vehicle's line sheet did not close")
        XCTAssertTrue(waitUntil(10) { self.tapLayer(app).hasPrefix("vela-transit-vehicles") },
                      "the tap registry did not reach the vehicle layer: \(layersDebug(app))")
        report("map_transit_vehicle_tap", 1)

        // 3. The globe pass: the same hub payload must survive the style reload of G-2.
        openLayers(app)
        let globe = app.buttons["layer-globe"]
        XCTAssertTrue(revealInSheet(globe, in: app), "no Globe row")
        if globe.value as? String != "on" { globe.tap() }
        XCTAssertTrue(waitUntil(30) {
            (self.debugText("globe-debug") ?? "").contains("globe_projection=globe")
        }, "the globe did not switch: \(debugText("globe-debug") ?? "no line")")
        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitForMapVehicles(app, atLeast: 1),
                      "the globe switch lost the vehicles: \(tapChain(app))")
        sleep(5)
        shot("transit-map-globe")
        report("map_transit_globe", 1)

        // Leave the shared projection at Mercator for the rest of the suite.
        openLayers(app)
        XCTAssertTrue(revealInSheet(globe, in: app), "no Globe row after the globe pass")
        if globe.value as? String == "on" { globe.tap() }
        XCTAssertTrue(waitUntil(30) {
            (self.debugText("globe-debug") ?? "").contains("globe_projection=mercator")
        }, "the map did not return to Mercator: \(debugText("globe-debug") ?? "no line")")
        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitForMapLines(app, atLeast: 1),
                      "the Mercator reload lost the lines: \(tapChain(app))")

        // 4. A tap on a drawn line opens the shared line sheet, not a stop board. This runs last:
        // the sheet draws one whole line on the map, replacing the live set until the panel reloads.
        tapCentre(app, offset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(app.otherElements["transit-line-sheet"].waitForExistence(timeout: 20),
                      "a tap on the drawn line opened no line sheet: \(layersDebug(app))")
        XCTAssertTrue(app.descendants(matching: .any)["transit-line-badge"].waitForExistence(timeout: 10),
                      "the line sheet opened without its badge")
        XCTAssertTrue(badge(app).label.contains("U2"),
                      "the line tap opened another line: \(badge(app).label)")
        app.buttons["transit-line-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.otherElements["transit-line-sheet"].exists },
                      "the line sheet did not close")
        XCTAssertTrue(waitUntil(10) { self.tapLayer(app).hasPrefix("vela-transit-line") },
                      "the tap registry did not reach a line layer: \(layersDebug(app))")
        report("map_transit_line_tap", 1)
    }

    private func openTrip(_ app: XCUIApplication) {
        let open = app.buttons["transit-trip-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "no trip button on the card")
        open.tap()
        XCTAssertTrue(app.buttons["transit-trip-close"].waitForExistence(timeout: 20),
                      "the trip screen did not open")
    }

    private func closeTrip(_ app: XCUIApplication) {
        app.buttons["transit-trip-close"].tap()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 20),
                      "the guidance card did not return")
    }

    private func openLive(_ app: XCUIApplication) {
        app.buttons["transit-live-open"].tap()
        XCTAssertTrue(app.buttons["transit-live-close"].waitForExistence(timeout: 20),
                      "the live panel did not open")
    }

    private func closeLive(_ app: XCUIApplication) {
        app.buttons["transit-live-close"].tap()
        XCTAssertTrue(waitUntil(10) { !app.buttons["transit-live-close"].exists },
                      "the live panel did not close")
    }

    private func tapCentre(_ app: XCUIApplication, offset: CGVector) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map element")
        map.coordinate(withNormalizedOffset: offset).tap()
    }

    private func waitForMapLines(_ app: XCUIApplication, atLeast count: Int) -> Bool {
        waitUntil(20) { self.mapCount(app, "transit_lines") >= count }
    }

    private func waitForMapVehicles(_ app: XCUIApplication, atLeast count: Int) -> Bool {
        waitUntil(20) {
            self.mapCount(app, "transit_vehicles") >= count
                && self.mapCount(app, "transit_estimated") == 1
        }
    }

    private func tapChain(_ app: XCUIApplication) -> String {
        debugText("tap-chain-debug") ?? "no tap chain"
    }

    private func layersDebug(_ app: XCUIApplication) -> String {
        debugText("layers-debug") ?? "no layers debug"
    }

    private func tapLayer(_ app: XCUIApplication) -> String {
        for part in layersDebug(app).split(separator: " ") where part.hasPrefix("tap_layer=") {
            return String(part.dropFirst("tap_layer=".count))
        }
        return ""
    }

    private func badge(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["transit-line-badge"]
    }

    private func mapCount(_ app: XCUIApplication, _ key: String) -> Int {
        for part in tapChain(app).split(separator: " ") where part.hasPrefix("\(key)=") {
            return Int(part.dropFirst(key.count + 1)) ?? -1
        }
        return -1
    }

    private func intValue(_ app: XCUIApplication, _ key: String, id: String) -> Int? {
        let element = app.staticTexts[id]
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("\(key)=") {
            return Int(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func openLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
    }
}
