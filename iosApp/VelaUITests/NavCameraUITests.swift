import XCTest

/// NAV-CAMERA: the drive camera keeps the car in the lower third, heading up along the road
/// geometry, with speed zoom and the optional turn framing. Overview fits the whole remaining
/// route and the next tap, or the next maneuver, returns to the same drive camera.
final class NavCameraUITests: VelaUITestCase {
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

    func testThirdOfScreenZoomAndOverview() throws {
        let app = startDrive()
        let banner = app.otherElements["nav-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "no nav banner")

        // The car sits in the lower third and the camera is tilted and zoomed for the drive.
        XCTAssertTrue(waitUntil(20) { (Int(self.value("carpad") ?? "") ?? 0) >= 66 },
                      "the car did not settle in the lower third: \(debugText("nav-debug") ?? "none")")
        XCTAssertGreaterThanOrEqual(Int(value("camtilt") ?? "0") ?? 0, 40,
                                    "the drive camera is not tilted")
        let zoom = Double(value("camzoom") ?? "") ?? 0
        XCTAssertGreaterThan(zoom, 15.0, "the drive zoom did not reach the street range")
        XCTAssertLessThanOrEqual(zoom, 19.0, "the drive zoom went past the style's range")
        report("nav_camera_third", "1")
        report("nav_camera_zoom", value("camzoom") ?? "?")
        shot("nav-camera-tilt")

        // Overview fits the whole remaining route in one action. The drive is paused first: a
        // maneuver reached while the camera is checked ends the overview by design, and the read
        // would then see the drive camera instead of the fitted one.
        let pause = app.buttons["nav-pause"]
        if pause.exists {
            pause.tap()
            XCTAssertTrue(waitUntil(5) { self.value("paused") == "1" }, "the drive did not pause")
        }
        let overview = app.buttons["nav-overview"]
        XCTAssertTrue(overview.exists, "no overview control in the drive bar")
        overview.tap()
        // The pitch is read in the same breath as the overview state: a step change ends the
        // overview by design, and a later read then shows the drive camera again.
        let flat = waitUntil(10) {
            self.value("camoverview") == "1" && self.value("camfollow") == "0"
                && self.value("camtilt") == "0"
        }
        report("nav_overview_pitch", value("camtilt") ?? "?")
        XCTAssertTrue(flat, "the overview did not open flat: \(debugText("nav-debug") ?? "none")")
        XCTAssertTrue(waitUntil(10) { (Double(self.value("camzoom") ?? "") ?? 99) < zoom },
                      "the overview did not pull the camera back")
        shot("nav-camera-overview")
        report("nav_camera_overview", "1")

        // A second tap returns to the same drive camera, not to a new one.
        overview.tap()
        XCTAssertTrue(waitUntil(10) {
            self.value("camoverview") == "0" && self.value("camfollow") == "1"
        }, "the second tap did not restore the drive camera")
        XCTAssertTrue(waitUntil(10) { (Int(self.value("carpad") ?? "") ?? 0) >= 66 },
                      "the car did not return to the lower third")
        let returned = Double(value("camzoom") ?? "") ?? 0
        XCTAssertGreaterThan(returned, 15.0,
                             "the return stayed at the overview zoom \(returned), not the drive zoom")
        XCTAssertEqual(value("camoverview"), "0", "the overview state survived the return")
        shot("nav-camera-third")
    }

    private func startDrive(extraArguments: [String] = []) -> XCUIApplication {
        let app = launch(
            camera: "sf",
            followUser: true,
            arguments: ["-VelaOpenURL", fixtureDrive] + extraArguments)
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
        return app
    }

    private func value(_ key: String) -> String? {
        field(key, in: "nav-debug")
    }

    private func routeValue(_ key: String) -> String? {
        field(key, in: "route-debug")
    }

    private func field(_ key: String, in identifier: String) -> String? {
        guard let line = debugText(identifier) else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }
}
