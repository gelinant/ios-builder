import XCTest

/// SELECTION-SYNC: one selection, visible on the map and in the lists. The scenario drives the
/// vehicles panel and the reachability panel of the recorded fixtures, selects a row, then checks
/// the map halo and the shared selection line, and returns through a map tap on the same symbol.
///
/// The map and the trip guidance cannot both take a tap: `MapScreen` ignores map taps while a trip
/// is active. The test therefore reads the model in both directions, and the row it tapped on the
/// list is the exact id the map tap reports afterwards (`selection_id`), which is what a reopened
/// panel would highlight and scroll to.
final class SelectionSyncUITests: VelaUITestCase {
    /// U2's estimate sits exactly under the centre, and S7 is far enough at z17 that a list tap
    /// recentres the map on it. The centre is then S7 for the map-to-list direction.
    private let vehicleCamera = "52.5225,13.4125,17"
    /// The reachability fixture is the recorded Ferry Building reply, at z17 around the first stop.
    private let stopCamera = "37.7955,-122.3937,17"

    func testVehicleAndStopSelectionTravelBothWays() {
        vehicleSelection()
        stopSelection()
    }

    // MARK: - Vehicle

    private func vehicleSelection() {
        let app = launch(camera: vehicleCamera)
        openTrip(app)
        openLive(app)
        app.buttons["transit-live-tab-vehicles"].tap()
        let toggle = app.switches["transit-vehicles-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no vehicles switch")
        if toggle.value as? String != "1" { toggle.tap() }
        XCTAssertTrue(waitUntil(20) {
            (self.intValue(app, "vehicles", id: "transit-vehicles-debug") ?? 0) > 0
        }, "no estimated vehicle was reported")

        // List -> map: the row tap selects the shared entity and the row says so.
        let row = reveal("transit-vehicle", in: "transit-live-sheet", app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no vehicle row")
        row.tap()
        XCTAssertTrue(waitUntil(10) {
            (self.selection(app, "selection_source") == "list"
                && self.selection(app, "selection_kind") == "vehicle"
                && self.selection(app, "selection_halo") == "1")
        }, "the vehicle row did not select on the shared model: \(self.tapChain(app))")
        report("selection_source", "list")
        report("selection_kind", "vehicle")
        report("selection_halo", 1)
        XCTAssertEqual(row.value as? String, "selected",
                       "the tapped vehicle row did not draw its selection style")
        sleep(2)
        shot("selection-list-vehicle")

        let listId = selection(app, "selection_id") ?? "-"
        closeLive(app)
        closeTrip(app)
        endTransit(app)

        // Map -> list: the same S7 estimate is now under the map centre. Its tap must replace the
        // list selection with a map one and keep the same identity, which is the row key.
        XCTAssertTrue(waitUntil(10) { self.mapCenter(app) })
        tapMap(app, offset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(waitUntil(15) {
            self.selection(app, "selection_source") == "map"
                && self.selection(app, "selection_kind") == "vehicle"
                && self.selection(app, "selection_halo") == "1"
        }, "the map vehicle tap did not select the shared model: \(self.tapChain(app))")
        XCTAssertEqual(selection(app, "selection_id"), listId,
                       "the map tap and the row named two different vehicles: \(tapChain(app))")
        report("selection_source", "map")
        report("selection_kind", "vehicle")
        report("selection_halo", 1)
        report("selection_row_match", 1)
        if app.buttons["transit-line-close"].waitForExistence(timeout: 5) {
            app.buttons["transit-line-close"].tap()
            XCTAssertTrue(waitUntil(10) { !app.otherElements["transit-line-sheet"].exists },
                          "the line card did not close")
        }
        sleep(3)
        shot("selection-map-vehicle")
        app.terminate()
    }

    // MARK: - Stop

    private func stopSelection() {
        let app = launch(camera: stopCamera)
        openTrip(app)
        openLive(app)
        app.buttons["transit-live-tab-reach"].tap()
        app.buttons["transit-live-reach-load"].tap()
        XCTAssertTrue(waitUntil(20) {
            (self.intValue(app, "stops", id: "transit-live-reach-debug") ?? 0) > 0
        }, "the reachability panel loaded no stop")

        let row = reveal("transit-live-reach-stop", in: "transit-live-sheet", app: app)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no reachable stop row")
        row.tap()
        XCTAssertTrue(waitUntil(10) {
            self.selection(app, "selection_source") == "list"
                && self.selection(app, "selection_kind") == "stop"
                && self.selection(app, "selection_halo") == "1"
        }, "the stop row did not select on the shared model: \(self.tapChain(app))")
        report("selection_source", "list")
        report("selection_kind", "stop")
        report("selection_halo", 1)
        XCTAssertEqual(row.value as? String, "selected",
                       "the tapped stop row did not draw its selection style")

        // The list selection recentres the map on the stop. Closing the panels leaves the halo on
        // the map, which is the screenshot the contract asks for.
        closeLive(app)
        closeTrip(app)
        endTransit(app)
        XCTAssertTrue(waitUntil(10) { self.mapCenter(app) })
        sleep(3)
        shot("selection-stop")

        // Map -> list: the centred stop is the reachability dot. Its tap is a map-source stop
        // selection with the same kind; the panels read this same value when reopened.
        tapMap(app, offset: CGVector(dx: 0.5, dy: 0.5))
        XCTAssertTrue(waitUntil(15) {
            self.selection(app, "selection_source") == "map"
                && self.selection(app, "selection_kind") == "stop"
                && self.selection(app, "selection_halo") == "1"
        }, "the map stop tap did not select the shared model: \(self.tapChain(app))")
        report("selection_source", "map")
        report("selection_kind", "stop")
        report("selection_halo", 1)
        if app.buttons["transit-board-close"].waitForExistence(timeout: 5) {
            app.buttons["transit-board-close"].tap()
        } else if app.buttons["map-tap-card-close"].waitForExistence(timeout: 2) {
            app.buttons["map-tap-card-close"].tap()
        }
        app.terminate()
    }

    // MARK: - Launch and helpers

    private func launch(camera: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", camera,
            "-VelaDeterministic", "YES",
            "-VelaResetSettings", "YES",
            "-VelaTransitFixture", "YES",
            "-VelaTransitAdvancedFixture", "YES",
            "-VelaTransitVehicleFixture", "YES",
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

    private func endTransit(_ app: XCUIApplication) {
        let end = app.buttons["transit-end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10), "no End button on the card")
        end.tap()
        XCTAssertTrue(app.buttons["map-actions-open"].waitForExistence(timeout: 20),
                      "the browser chrome did not return after the trip")
    }

    private func tapMap(_ app: XCUIApplication, offset: CGVector) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map element")
        map.coordinate(withNormalizedOffset: offset).tap()
    }

    /// The map exists and is laid out, so a centre tap lands on the map rather than a transition.
    private func mapCenter(_ app: XCUIApplication) -> Bool {
        let map = app.otherElements["map"]
        return map.exists && map.frame.height > 100
    }

    private func tapChain(_ app: XCUIApplication) -> String {
        text(app, "tap-chain-debug") ?? "no tap chain"
    }

    private func selection(_ app: XCUIApplication, _ key: String) -> String? {
        for part in tapChain(app).split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
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
}
