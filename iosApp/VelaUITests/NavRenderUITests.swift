import XCTest

/// NAV-RENDER: the live route drawn as a gray driven part and congestion-coloured road ahead,
/// the two manoeuvre arrows at the points the banner names, and the lane row on the approach.
/// The store and core tests prove the selection; this scenario proves the layers reach the map.
final class NavRenderUITests: VelaUITestCase {
    private let fixtureDrive = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving"

    override func tearDown() {
        if let app, app.buttons["nav-end"].exists {
            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testCongestionGreyAndRoadAhead() throws {
        let app = launch(
            camera: "sf",
            followUser: true,
            arguments: ["-VelaOpenURL", fixtureDrive,
                        "-VelaNavBannerFixture", "YES",
                        "-VelaNavRenderFixture", "YES"])
        let chooser = app.otherElements["route-sheet"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "the directions link did not open the chooser")
        if routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        let start = app.buttons["route-start"]
        XCTAssertTrue(waitUntil(120) { start.exists && start.isEnabled },
                      "no driving route: \(debugText("route-debug") ?? "none")")
        start.tap()
        XCTAssertTrue(waitUntil(20) { self.value("nav") == "1" }, "navigation did not start")

        // The route is split at the car and at the congestion span: at least the gray and the
        // free-flow piece, plus the injected heavy one.
        XCTAssertTrue(
            waitUntil(20) { (Int(self.value("navsegments") ?? "0") ?? 0) >= 2 },
            "no navigation route pieces: \(debugText("nav-debug") ?? "none")")
        let segments = Int(value("navsegments") ?? "0") ?? 0
        XCTAssertEqual(value("navcongestion"), "1", "the congestion piece did not reach the map")
        XCTAssertGreaterThanOrEqual(segments, 3, "the gray cut or the congestion piece was not split")
        shot("nav-congestion")
        report("nav_route_segments", segments)
        report("nav_congestion", 1)

        XCTAssertTrue(
            waitUntil(20) { (Int(self.value("navahead") ?? "0") ?? 0) >= 2 },
            "fewer than two road-ahead arrows: \(debugText("nav-debug") ?? "none")")
        let arrows = Int(value("navahead") ?? "0") ?? 0
        XCTAssertEqual(value("navahead"), "2", "the following manoeuvre arrow is missing")
        XCTAssertEqual(value("instr"), "1", "the banner lost its instruction")
        shot("nav-road-ahead")
        report("nav_road_ahead", arrows)

        XCTAssertTrue(
            waitUntil(20) { (Int(self.value("navlanes") ?? "0") ?? 0) >= 1 },
            "no lane row on the approach: \(debugText("nav-debug") ?? "none")")
        XCTAssertEqual(value("lanes"), "4", "the shared model lost its lanes")
        shot("nav-lanes-map")
        report("nav_lanes_map", value("navlanes") ?? "?")
    }

    private func value(_ key: String) -> String? {
        guard let line = debugText("nav-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
