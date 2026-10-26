import XCTest

/// N-2 route-alert scenario. Overpass replies are derived from the requested route by a Debug-only
/// URLProtocol, so speed, posted-limit and camera checks do not depend on live OSM coverage.
final class NavAlertsUITests: VelaUITestCase {
    override func tearDown() {
        if let app, app.buttons["nav-end"].exists {
            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testRouteAlertsFromFixtureProvider() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaNavAlertsFixture", "YES"])
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("Ferry Building\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no fixture destination result")
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(90) {
            self.routeValue("loading") == "0" && (Int(self.routeValue("routes") ?? "") ?? 0) > 0
        }, "no driving route: \(debugText("route-debug") ?? "none")")
        app.buttons["route-start"].tap()
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")

        XCTAssertTrue(app.otherElements["nav-speed"].waitForExistence(timeout: 10), "no speed pill")
        XCTAssertTrue(waitUntil(20) { app.staticTexts["nav-speed-limit"].exists },
                      "the fixture maxspeed way did not produce a posted limit")
        shot("nav-speed")
        report("nav_speed_limit", intValue("limit") ?? -1)

        XCTAssertTrue(app.otherElements["nav-camera-alert"].waitForExistence(timeout: 30),
                      "the fixture camera did not alert: \(debugText("nav-debug") ?? "none")")
        shot("nav-camera")
        report("nav_camera_groups", intValue("alertgroups") ?? -1)
        XCTAssertGreaterThan(intValue("alertgroups") ?? 0, 0)

        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "0" && self.value("active") == "0" })
        XCTAssertTrue(field.waitForExistence(timeout: 5), "browse chrome was not restored")
        if value("actenabled") == "1" {
            XCTAssertTrue(waitUntil(5) { self.value("activity") == "0" }, "Live Activity survived End")
        }
        report("nav_alerts_end", "restored")
    }

    private func routeValue(_ key: String) -> String? {
        parse(debugText("route-debug"), key)
    }

    private func value(_ key: String) -> String? {
        parse(debugText("nav-debug"), key)
    }

    private func intValue(_ key: String) -> Int? {
        value(key).flatMap(Int.init)
    }

    private func parse(_ line: String?, _ key: String) -> String? {
        guard let line else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
