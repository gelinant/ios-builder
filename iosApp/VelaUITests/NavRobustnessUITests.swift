import XCTest

/// N-3: pause, GPS loss and recovery on the Market Street replay, with one Live Activity and one
/// session throughout. The host's sim_route_arm watcher starts the fixture when guidance begins.
final class NavRobustnessUITests: VelaUITestCase {
    override func tearDown() {
        if let app, app.buttons["nav-end"].exists {
            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testPauseGpsLossResumeAndEnd() throws {
        let app = launch(camera: "sf", followUser: true, arguments: ["-VelaNavRobustnessTest", "YES"])
        let field = app.textFields["search-field"]
        sleep(4)
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)

        var picked = false
        for name in ["Paper Son Coffee", "Delah Coffee", "Origin Lab Coffee"] {
            let row = rows.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
            guard row.exists else { continue }
            for _ in 0..<8 where !row.isHittable {
                app.scrollViews.firstMatch.swipeUp()
            }
            if row.isHittable {
                row.tap()
                picked = true
                break
            }
        }
        if !picked {
            rows.firstMatch.tap()
        }
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
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "1" }, "navigation did not start")
        let checksActivity = value("actenabled") == "1"
        let activityRequests = intValue("actrequests") ?? 0
        if checksActivity {
            XCTAssertTrue(waitUntil(10) { self.value("activity") == "1" }, "no Live Activity on Start")
            XCTAssertGreaterThan(activityRequests, 0, "ActivityKit request was not made")
        }

        // ci-ipa.sh arms the sf-market replay on "nav replay: start". Another navigation
        // scenario may still own the simulated drive, so movement is reported, not required:
        // NavUITests proves progress, and this scenario is about the hold and the GPS loss.
        let initialLeft = intValue("left")
        XCTAssertNotNil(initialLeft)
        let moving = waitUntil(30) {
            guard let before = initialLeft, let now = self.intValue("left") else { return false }
            return now < before
        }
        report("nav_robustness_replay", moving ? "sf-market" : "not-moving")

        let pause = app.buttons["nav-pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "no Pause control during guidance")
        pause.tap()
        XCTAssertTrue(waitUntil(10) { self.value("paused") == "1" }, "Pause did not hold the drive")
        XCTAssertEqual(value("follow"), "0", "the camera kept following while paused")
        XCTAssertTrue(self.element("nav-paused").waitForExistence(timeout: 10), "no Paused state")
        let pausedLeft = intValue("left")
        XCTAssertNotNil(pausedLeft)
        sleep(3)
        XCTAssertEqual(intValue("left"), pausedLeft, "the figures moved while paused")
        shot("nav-paused")
        report("nav_pause", "frozen")

        // Background and foreground with the screen locked by the system: the drive must survive.
        XCUIDevice.shared.press(.home)
        sleep(3)
        app.activate()
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 15), "drive ended in the background")
        XCTAssertEqual(value("nav"), "1")
        XCTAssertEqual(value("active"), "1")
        XCTAssertEqual(value("paused"), "1")
        XCTAssertTrue(waitUntil(5) { self.value("bg") == "0" }, "the app did not report the foreground")
        if checksActivity {
            XCTAssertEqual(value("activity"), "1", "the Live Activity did not survive the background")
            XCTAssertEqual(intValue("actrequests"), activityRequests, "a second Live Activity was requested")
        }
        report("nav_lifecycle", "background_foreground_kept_session")

        let resume = app.buttons["nav-resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "no Resume control")
        resume.tap()
        XCTAssertTrue(waitUntil(10) { self.value("paused") == "0" }, "Resume did not release the drive")
        XCTAssertEqual(value("follow"), "1", "Resume did not re-attach the camera")
        let continued = waitUntil(25) {
            guard let before = pausedLeft, let now = self.intValue("left") else { return false }
            return now < before
        }
        report("nav_resume", continued ? "continued" : "state-only")

        let starve = app.buttons["nav-test-starve"]
        XCTAssertTrue(starve.waitForExistence(timeout: 10), "no GPS-loss test control")
        starve.tap()
        XCTAssertTrue(waitUntil(30) { self.value("starved") == "1" },
                      "the no-GPS state did not appear: \(debugText("nav-debug") ?? "none")")
        // The estimator only starts while the drive was moving when fixes stopped. A shared
        // replay that has already reached its last point is honestly stationary, so the chip
        // and recovery are required here and the estimate is reported.
        _ = waitUntil(10) { self.value("reckoning") == "1" }
        XCTAssertEqual(value("nav"), "1", "GPS loss ended guidance")
        XCTAssertEqual(value("active"), "1")
        XCTAssertEqual(value("paused"), "0")
        XCTAssertTrue(self.element("nav-starved").waitForExistence(timeout: 5), "no no-GPS chip")
        shot("nav-starved")
        XCTAssertGreaterThan(intValue("suppressed") ?? 0, 0, "no fix was actually withheld")
        report("nav_starved", "1")
        report("nav_reckoning", value("reckoning") ?? "0")

        app.buttons["nav-test-gps"].tap()
        XCTAssertTrue(waitUntil(20) { self.value("starved") == "0" }, "guidance did not recover when fixes returned")
        XCTAssertTrue(app.otherElements["nav-banner"].exists, "the drive did not survive recovery")
        if checksActivity {
            XCTAssertEqual(value("activity"), "1", "recovery ended the Live Activity")
            XCTAssertEqual(intValue("actrequests"), activityRequests, "recovery requested a second Live Activity")
        }
        report("nav_gps_back", "1")

        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "0" && self.value("active") == "0" })
        XCTAssertTrue(field.waitForExistence(timeout: 5), "browse chrome was not restored")
        XCTAssertEqual(value("idle"), "0")
        XCTAssertEqual(value("background"), "0")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { self.value("activity") == "0" }, "Live Activity survived End")
        }
        report("nav_robustness_end", "restored")
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func value(_ key: String) -> String? {
        guard let line = debugText("nav-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ key: String) -> Int? {
        value(key).flatMap(Int.init)
    }
}
