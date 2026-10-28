import XCTest

/// NAV-FREEDRIVE: driving with no destination. The chrome shows the GPS speed, the posted limit
/// read from OSM around the fix, the road under the car and its shield, and the switch that strips
/// the map to what a driver needs. The Overpass fixture answers the free-drive query so the limit
/// does not depend on live OSM data.
final class FreeDriveUITests: VelaUITestCase {
    override func tearDown() {
        if let app, app.buttons["free-exit"].exists, app.buttons["free-exit"].isHittable {
            app.buttons["free-exit"].tap()
            _ = waitUntil(5) { self.value("free") == "0" }
        }
        super.tearDown()
    }

    func testSpeedLimitRoadShieldAndSimpleMap() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaNavAlertsFixture", "YES"])
        let open = app.buttons["free-drive-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "no free-drive entry on the map")
        open.tap()

        let chrome = app.descendants(matching: .any)["free-drive-chrome"]
        XCTAssertTrue(chrome.waitForExistence(timeout: 15), "the free-drive chrome did not open")
        XCTAssertTrue(waitUntil(20) { self.value("free") == "1" },
                      "the store did not enter free driving: \(debugText("free-debug") ?? "none")")
        XCTAssertEqual(value("nav"), "0", "free driving must not start a navigation session")

        // The limit and the road come from the fake Overpass reply around the simulated fix.
        XCTAssertTrue(waitUntil(60) { self.value("limit") == "80" },
                      "no real posted limit reached the badge: \(debugText("free-debug") ?? "none")")
        XCTAssertTrue(app.staticTexts["free-speed-limit"].exists, "no speed-limit sign")
        XCTAssertTrue(waitUntil(15) { app.staticTexts["free-road"].exists }, "no road name")
        XCTAssertEqual(app.staticTexts["free-road"].label, "Market Street")
        XCTAssertTrue(app.descendants(matching: .any)["free-road-shield"].firstMatch.exists,
                      "the road's route number has no shield")
        report("free_drive_limit", value("limit") ?? "?")

        // The fixture replay starts on the free drive's replay line: the speed comes from GPS.
        let speed = app.staticTexts["free-speed-value"]
        XCTAssertTrue(speed.waitForExistence(timeout: 30), "no speed value")
        XCTAssertTrue(waitUntil(90) { (Int(speed.label) ?? 0) > 0 },
                      "the GPS speed stayed at zero: \(debugText("free-debug") ?? "none")")
        report("free_drive_speed", speed.label)
        shot("free-drive-speed-limit")

        // The simple map: places, transit and browse overlays leave; the driver keeps the road.
        let simple = app.buttons["free-simple-map"]
        XCTAssertTrue(simple.exists, "no simple-map switch")
        XCTAssertEqual(simple.value as? String, "off")
        simple.tap()
        XCTAssertTrue(waitUntil(10) { self.value("simple") == "1" },
                      "the simple-map switch did not reach the map")
        XCTAssertEqual(simple.value as? String, "on")
        shot("free-drive-simple-map")
        report("free_drive_simple", value("simple") ?? "?")

        // Leaving is immediate: no confirmation, no route, no notification.
        app.buttons["free-exit"].tap()
        // The debug line lives in the free-drive chrome, so its disappearance is the exit proof;
        // the browse chrome's own entry button must be back.
        XCTAssertTrue(waitUntil(10) { !chrome.exists }, "the free-drive chrome stayed after Exit")
        XCTAssertTrue(app.buttons["free-drive-open"].waitForExistence(timeout: 10),
                      "the map did not return after free driving")
        report("free_drive_exit", "1")
    }

    private func value(_ key: String) -> String? {
        guard let line = debugText("free-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
