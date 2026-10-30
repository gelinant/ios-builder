import XCTest

/// A-3: the keyless NESO carbon layer for Great Britain, the Cloudflare Radar list, and the two
/// explicit key states. The Debug fixtures answer both feeds, so the run needs no provider token
/// and no live NESO call. The screenshots are `energy.png`, `radar.png` and
/// `energy-key-required.png`; the summary gets `energy_source=neso` and `radar_state=fresh` or
/// `radar_state=key_required`.
final class EnergyRadarUITests: VelaUITestCase {
    func testCarbonAndRadar() {
        let fresh = launch(
            camera: "54.0,-2.0,5",
            arguments: ["-VelaResetSettings", "YES",
                        "-VelaWorldEnergyFixture", "YES",
                        "-VelaWorldEnergyKeys", "YES"])
        enableEnergy(fresh)
        panForRefresh(fresh)

        let freshDebug = debugRow(fresh, "energy-debug")
        XCTAssertTrue(freshDebug.contains("energy_source=neso"),
                      "the layer did not report NESO: \(freshDebug)")
        XCTAssertTrue(freshDebug.contains("radar_state=fresh"),
                      "the Radar fixture was not fresh: \(freshDebug)")
        XCTAssertTrue(freshDebug.contains("energy_regions=14"),
                      "the 14 British regions are not all present: \(freshDebug)")
        XCTAssertFalse(freshDebug.contains("fixture-radar-token"),
                       "the Radar token reached the debug line: \(freshDebug)")
        XCTAssertFalse(freshDebug.contains("fixture-electricity-maps-key"),
                       "the Electricity Maps key reached the debug line: \(freshDebug)")
        report("energy_source", "neso")
        report("radar_state", "fresh")

        fresh.buttons["layers-close"].tap()
        sleep(1)
        fresh.otherElements["map"].swipeRight()
        sleep(3)
        shot("energy")

        tapLayers(fresh)
        let radar = row(fresh, "energy-radar-fixture-outage-gb")
        for _ in 0..<10 where !radar.isHittable { fresh.swipeUp() }
        XCTAssertTrue(radar.exists, "no Radar outage row")
        shot("radar")

        let missing = launch(
            camera: "54.0,-2.0,5",
            arguments: ["-VelaResetSettings", "YES",
                        "-VelaWorldEnergyFixture", "YES",
                        "-VelaWorldEnergyNoKeys", "YES"])
        enableEnergy(missing)
        panForRefresh(missing)

        let missingDebug = debugRow(missing, "energy-debug")
        XCTAssertTrue(missingDebug.contains("energy_source=neso"), missingDebug)
        XCTAssertTrue(missingDebug.contains("radar_state=key_required"),
                      "a missing Radar token must be stated: \(missingDebug)")
        XCTAssertTrue(missingDebug.contains("electricity_maps=key_required"),
                      "a missing Electricity Maps key must be stated: \(missingDebug)")

        let energyKey = row(missing, "energy-electricity-maps-key")
        for _ in 0..<10 where !energyKey.isHittable { missing.swipeUp() }
        XCTAssertTrue(energyKey.exists, "no Electricity Maps key-required row")
        XCTAssertTrue(energyKey.label.contains("key required"),
                      "the Electricity Maps row does not say key required: \(energyKey.label)")
        let radarKey = row(missing, "energy-radar-key")
        for _ in 0..<6 where !radarKey.isHittable { missing.swipeUp() }
        XCTAssertTrue(radarKey.exists, "no Radar token-missing row")
        XCTAssertTrue(radarKey.label.contains("token missing"),
                      "the Radar row does not say token missing: \(radarKey.label)")
        shot("energy-key-required")
        report("radar_state", "key_required")
        missing.buttons["layers-close"].tap()
        disableEnergy(missing)
    }

    private func tapLayers(_ app: XCUIApplication) {
        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")
    }

    private func enableEnergy(_ app: XCUIApplication) {
        tapLayers(app)
        let energy = app.buttons["world-layer-energy"]
        for _ in 0..<10 where !energy.isHittable { app.swipeUp() }
        XCTAssertTrue(energy.exists, "no energy layer row")
        XCTAssertTrue(energy.isEnabled, "A-3 must install the energy layer")
        // The settings suite does not survive -VelaResetSettings, so a previous scenario may have
        // left the switch on. Turn it on only when it is off.
        if energy.value as? String != "on" { energy.tap() }
        XCTAssertTrue(waitUntil(5) { app.buttons["world-layer-energy"].value as? String == "on" },
                      "the energy switch did not turn on")
        app.buttons["layers-close"].tap()
        sleep(1)
    }

    /// Leaves the shared settings suite as WLD-1 expects: the next scenario must see every world
    /// layer off.
    private func disableEnergy(_ app: XCUIApplication) {
        tapLayers(app)
        let energy = app.buttons["world-layer-energy"]
        for _ in 0..<10 where !energy.isHittable { app.swipeUp() }
        if energy.exists && energy.isHittable && energy.value as? String == "on" { energy.tap() }
        app.buttons["layers-close"].tap()
    }

    /// The host refreshes on a camera move, not when the switch flips. One pan fetches, a second
    /// pan applies the received polygons to the style.
    private func panForRefresh(_ app: XCUIApplication) {
        let map = app.otherElements["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 30), "no map")
        map.swipeLeft()
        XCTAssertTrue(waitUntil(20) {
            app.buttons["layers-button"].exists
        }, "the map did not settle after the first pan")
        map.swipeRight()
        sleep(2)
    }

    private func debugRow(_ app: XCUIApplication, _ id: String) -> String {
        tapLayers(app)
        let element = row(app, id)
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.exists, "no \(id) row")
        return element.label
    }

    private func row(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.buttons["world-row-\(id)"]
    }
}
