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

    /// L208-L209: the speaker button's middle state mutes guidance, keeps the camera and speeding
    /// alerts as a chime, and writes Android's two settings keys. The JVM test proves the values;
    /// this scenario proves the banner control and the silence.
    func testAlertsOnlySilencesGuidanceAndKeepsAlerts() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaNavAlertsFixture", "YES"])
        startDrive(app)
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")
        XCTAssertTrue(waitUntil(20) { self.value("nav") == "1" }, "navigation did not start")
        XCTAssertEqual(value("voicemode"), "on")

        let before = intValue("voice") ?? 0
        app.buttons["nav-voice"].tap()
        XCTAssertTrue(waitUntil(5) { self.value("voicemode") == "alerts" },
                      "the speaker button did not reach Alerts only: \(debugText("nav-debug") ?? "none")")
        XCTAssertTrue(app.buttons["nav-voice"].label.contains("Alerts"),
                      "the speaker button does not name the Alerts only state")
        shot("nav-alerts-only")

        // The fixture guarantees a camera on this route; the card stays visible in Alerts only.
        XCTAssertTrue(app.otherElements["nav-camera-alert"].waitForExistence(timeout: 30),
                      "the camera alert disappeared in Alerts only: \(debugText("nav-debug") ?? "none")")
        sleep(3)
        XCTAssertEqual(intValue("voice") ?? 0, before,
                       "guidance was spoken in Alerts only")

        app.buttons["nav-voice"].tap()
        XCTAssertTrue(waitUntil(5) { self.value("voicemode") == "off" }, "no Off state")
        app.buttons["nav-voice"].tap()
        XCTAssertTrue(waitUntil(5) { self.value("voicemode") == "on" }, "no return to On")
        shot("nav-alerts-cycle")
        report("nav_alerts_only", "on_alerts_off_on")

        endDrive(app)
    }

    /// L168-L169: one local notification while guidance runs in the background, and the tap
    /// bridge back into the same drive. The debug button calls the delegate's own handler, so the
    /// scenario does not depend on hitting a system banner.
    func testBackgroundNotificationAndTapBridge() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: ["-VelaNavNotificationTest", "YES"])
        startDrive(app)
        allowNotifications()
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")
        XCTAssertTrue(waitUntil(20) { self.value("nav") == "1" }, "navigation did not start")
        allowNotifications()

        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20),
                      "the drive did not survive the background")
        allowNotifications()

        let authorization = value("notifauth") ?? "unknown"
        report("nav_notification_authorization", authorization)
        if authorization == "granted" {
            XCTAssertGreaterThan(intValue("notifpost") ?? 0, 0,
                                 "no local notification was posted on background")
        } else {
            report("nav_notification_post", "not_asserted_\(authorization)")
        }

        let bridge = app.buttons["nav-test-notify-open"]
        XCTAssertTrue(bridge.waitForExistence(timeout: 10), "no notification-tap test control")
        bridge.tap()
        XCTAssertTrue(waitUntil(5) { self.value("notifopen") == "1" },
                      "the notification tap did not reach the drive: \(debugText("nav-debug") ?? "none")")
        XCTAssertEqual(value("nav"), "1", "the tap ended the drive")
        XCTAssertEqual(value("follow"), "1", "the tap did not re-attach the camera")
        shot("nav-alert-bridge")
        report("nav_notification_bridge", "same_drive")

        endDrive(app)
    }

    private func startDrive(_ app: XCUIApplication) {
        let field = app.textFields["search-field"]
        sleep(4)
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
    }

    private func endDrive(_ app: XCUIApplication) {
        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "0" && self.value("active") == "0" })
        report("nav_alerts_end", "restored")
    }

    private func allowNotifications() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 4) {
            allow.tap()
            sleep(1)
        }
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
