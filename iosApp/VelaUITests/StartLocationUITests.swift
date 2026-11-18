import XCTest

/// START-LOCATION. The harness grants location and sets the simulator to San Francisco before
/// these scenarios (scripts/ios/ci-ipa.sh), so the launch without `-VelaStartCamera` has a real
/// fix to open on. The map is deterministic, which also turns camera animation off.
final class StartLocationUITests: VelaUITestCase {
    /// The point sim_location_set sets before the UI scenarios.
    private let simulatedLatitude = 37.7749
    private let simulatedLongitude = -122.4194

    func testOpensOnTheSimulatedPosition() {
        let app = launchAtLaunchCamera(arguments: [])
        XCTAssertTrue(waitUntil(20) {
            app.staticTexts["start-debug"].label.contains("start_camera=position")
        }, "the map did not open on the position: \(startLine(app))")

        XCTAssertTrue(waitUntil(10) { distance(startLine(app)) <= 150 },
                      "the camera is not on the fix: \(startLine(app))")
        let center = center(startLine(app))
        XCTAssertEqual(center.latitude, simulatedLatitude, accuracy: 0.002)
        XCTAssertEqual(center.longitude, simulatedLongitude, accuracy: 0.002)
        XCTAssertGreaterThanOrEqual(center.zoom, 13,
                                    "the position opens on a city view, not the whole country")
        shot("start-location")
        report("start_camera", "position")
        report("start_distance_m", Int(distance(startLine(app))))
    }

    /// An incoming search link at Davis is a known point far from the simulated position. The
    /// link owns the camera and the late fix must not pull it back to San Francisco.
    func testIncomingLinkWinsOverThePosition() {
        let link = "https://www.google.com/maps/search/coffee/@38.5449,-121.7405,12z"
        let app = launchAtLaunchCamera(arguments: ["-VelaOpenURL", link])
        XCTAssertTrue(waitUntil(20) {
            app.staticTexts["start-debug"].label.contains("start_camera=explicit")
        }, "the link did not own the launch camera: \(startLine(app))")
        XCTAssertTrue(waitUntil(20) {
            let center = center(self.startLine(app))
            return abs(center.latitude - 38.5449) < 0.01
                && abs(center.longitude + 121.7405) < 0.01
        }, "the camera is not on the link's point: \(startLine(app))")
        XCTAssertFalse(startLine(app).contains("start_camera=position"),
                       "the position stole the camera from the link")
        shot("start-location-link")
        report("start_camera", "explicit")
        report("start_distance_m", 0)
    }

    /// Launches without `-VelaStartCamera`, so the position or the last camera decides. Waits for
    /// the map screen exactly as VelaUITestCase.launch does.
    private func launchAtLaunchCamera(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelaDeterministic", "YES"] + arguments
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60), "no map screen")
        return app
    }

    private func startLine(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["start-debug"]
        return label.exists ? label.label : ""
    }

    /// The value after `key=` up to the next space.
    private func number(_ line: String, _ key: String) -> Double {
        guard let range = line.range(of: key + "=") else { return -1 }
        let rest = line[range.upperBound...]
        let value = rest.prefix { $0 != " " }
        return Double(value) ?? -1
    }

    private func distance(_ line: String) -> Double {
        number(line, "start_distance_m")
    }

    /// `start_center=lat,lng,zoom` as written by MapScreen.
    private func center(_ line: String) -> (latitude: Double, longitude: Double, zoom: Double) {
        guard let range = line.range(of: "start_center=") else { return (0, 0, 0) }
        let parts = line[range.upperBound...].split(separator: ",")
        guard parts.count == 3, let latitude = Double(parts[0]),
              let longitude = Double(parts[1]), let zoom = Double(parts[2]) else {
            return (0, 0, 0)
        }
        return (latitude, longitude, zoom)
    }
}
