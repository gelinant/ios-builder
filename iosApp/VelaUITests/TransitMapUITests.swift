import XCTest

/// T2-WIRE: the panels publish their already-fetched transit data to the map hub, and the map
/// draws it without owning a model or sending a request. The scenario runs on the recorded Berlin
/// lines and vehicles of `-VelaTransitAdvancedFixture` and `-VelaTransitVehicleFixture`; the
/// San Francisco trip fixture only supplies the card that opens the live panel. Every capture is
/// taken after the trip is ended, so the pixels prove the hub, not the card and not the sheet.
///
/// The lines and the vehicles use two launches because their fixtures share Berlin but not a
/// useful camera: the line shot fits all five stretches at z14, and the vehicle shot centres the
/// U2 estimate at z15 so a tap on the map centre hits the dot without guessing an offset.
final class TransitMapUITests: VelaUITestCase {
    /// U2's second vertex in the recorded Berlin path, at z14 to keep every line in frame.
    private let lineCamera = "52.52205,13.41376,14"
    /// U2's estimated vehicle in the same fixture, at z15 so it sits exactly under the map centre.
    private let vehicleCamera = "52.5225,13.4125,15"

    func testLinesAndVehiclesOnTheMap() {
        let lineApp = launchTransitMap(camera: lineCamera)

        openTrip(lineApp)
        openLive(lineApp)
        lineApp.buttons["transit-live-tab-lines"].tap()
        lineApp.buttons["transit-live-lines-load"].tap()
        XCTAssertTrue(waitUntil(20) {
            (self.intValue(lineApp, "lines", id: "transit-live-lines-debug") ?? 0) > 0
        }, "the live panel loaded no line: \(text(lineApp, "transit-live-lines-debug") ?? "no line")")
        closeLive(lineApp)
        closeTrip(lineApp)
        endTransit(lineApp)

        XCTAssertTrue(waitForMapLines(lineApp, atLeast: 1),
                      "the lines never reached the map: \(tapChain(lineApp))")
        let drawnLines = mapCount(lineApp, "transit_lines")
        report("map_transit_lines", drawnLines)
        XCTAssertGreaterThan(drawnLines, 0, "the map drew no transit line: \(tapChain(lineApp))")
        sleep(3)
        shot("transit-map-lines")

        // The map centre is U2's vertex: a tap there opens the shared line sheet, not a stop board.
        tapMap(lineApp, offset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(lineApp.otherElements["transit-line-sheet"].waitForExistence(timeout: 20),
                      "a tap on the drawn line opened no line sheet: \(layersDebug(lineApp))")
        XCTAssertTrue(lineApp.descendants(matching: .any)["transit-line-badge"].waitForExistence(timeout: 10),
                      "the line sheet opened without its badge")
        XCTAssertTrue(badge(lineApp).label.contains("U2"),
                      "the line tap opened another line: \(badge(lineApp).label)")
        lineApp.buttons["transit-line-close"].tap()
        XCTAssertTrue(waitUntil(10) { !lineApp.otherElements["transit-line-sheet"].exists },
                      "the line sheet did not close")
        XCTAssertTrue(waitUntil(10) { self.tapLayer(lineApp).hasPrefix("vela-transit-line") },
                      "the tap registry did not reach a line layer: \(layersDebug(lineApp))")
        report("map_transit_line_tap", 1)
        lineApp.terminate()

        // Second launch: the vehicles, with the U2 estimate exactly at the map centre.
        let app = launchTransitMap(camera: vehicleCamera)
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
        endTransit(app)

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

        // A tap on the centred dot opens the same line sheet, not the line 6 pt beside it.
        tapMap(app, offset: CGVector(dx: 0.5, dy: 0.5))
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

        // The globe pass: the same hub payload must survive the style reload of G-2.
        openLayers(app)
        let globe = app.buttons["layer-globe"]
        XCTAssertTrue(revealInSheet(globe, in: app), "no Globe row")
        if globe.value as? String != "on" { globe.tap() }
        XCTAssertTrue(waitUntil(30) {
            (self.text(app, "globe-debug") ?? "").contains("globe_projection=globe")
        }, "the globe did not switch: \(text(app, "globe-debug") ?? "no line")")
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
            (self.text(app, "globe-debug") ?? "").contains("globe_projection=mercator")
        }, "the map did not return to Mercator: \(text(app, "globe-debug") ?? "no line")")
        app.buttons["layers-close"].tap()
    }

    /// The transit fixture opens its guidance card at launch, which intentionally replaces the
    /// browser chrome. Waiting for `search-field` would therefore fail; the card is the marker.
    private func launchTransitMap(camera: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", camera,
            "-VelaDeterministic", "YES",
            "-VelaResetSettings", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitAdvancedFixture", "YES",
            "-VelaTransitVehicleFixture", "YES",
            // The recorded trip would fit San Francisco; this keeps the Berlin launch camera.
            "-VelaTransitMapCamera", camera,
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["transit-card"].waitForExistence(timeout: 60),
                      "the transit fixture did not open its guidance card")
        return app
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

    /// Ending the trip brings the browser chrome back and leaves the hub's layers on the map.
    private func endTransit(_ app: XCUIApplication) {
        let end = app.buttons["transit-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10), "no End button on the card")
        end.tap()
        XCTAssertTrue(app.buttons["layers-button"].waitForExistence(timeout: 20),
                      "the browser chrome did not return after the trip")
    }

    private func tapMap(_ app: XCUIApplication, offset: CGVector) {
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
        text(app, "tap-chain-debug") ?? "no tap chain"
    }

    private func layersDebug(_ app: XCUIApplication) -> String {
        text(app, "layers-debug") ?? "no layers debug"
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

    private func text(_ app: XCUIApplication, _ id: String) -> String? {
        let element = app.staticTexts[id]
        return element.exists ? element.label : nil
    }

    private func openLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
    }
}
