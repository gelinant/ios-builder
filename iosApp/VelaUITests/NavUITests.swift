import XCTest

/// M5 end to end: a coffee route over the San Francisco fixture, Start, a Market Street replay,
/// decreasing guidance figures, camera follow and one real AVSpeechSynthesizer delegate callback.
final class NavUITests: VelaUITestCase {
    func testGuidedDriveAndEnd() throws {
        let app = launch(camera: "sf", followUser: true)
        let field = app.textFields["search-field"]
        sleep(4)
        field.tap()
        field.typeText("coffee\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)

        // These coffee stops lie along the Market Street fixture. The list changes over time, so
        // use the first one still present and retain the nearest-result fallback for the nav smoke.
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
        let initialLeft = intValue("left")
        XCTAssertNotNil(initialLeft)
        sleep(2)
        shot("nav-start")

        // ci-ipa.sh armed sim_route_start sf-market on the host; NavModel's start line released it.
        report("nav_replay", "sf-market")
        XCTAssertTrue(waitUntil(25) {
            guard let before = initialLeft, let now = self.intValue("left") else { return false }
            return now < before
        }, "distance left did not decrease: \(debugText("nav-debug") ?? "none")")
        sleep(2)
        shot("nav-driving")
        XCTAssertEqual(value("follow"), "1", "camera detached")
        XCTAssertGreaterThan(intValue("camera") ?? 0, 0, "map did not follow any fix")
        XCTAssertEqual(value("idle"), "1", "idle timer was not disabled")
        XCTAssertEqual(value("background"), "1", "background location was not armed")

        let voiceLine = debugText("nav-voice-debug") ?? ""
        XCTAssertGreaterThan(intValue("voice") ?? 0, 0, "no AVSpeechSynthesizer didStart callback")
        XCTAssertTrue(voiceLine.hasPrefix("spoken=") && !voiceLine.hasSuffix("text="), "no spoken line")
        report("nav_voice_count", intValue("voice") ?? 0)
        report("nav_voice_line", voiceLine.replacingOccurrences(of: " ", with: "_"))
        report("nav_initial_meters", initialLeft ?? -1)
        report("nav_driving_meters", intValue("left") ?? -1)
        report("nav_camera_updates", intValue("camera") ?? 0)

        app.buttons["nav-end"].tap()
        // iOS 26 exposes the confirmation's identifier on both nested accessibility buttons.
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "0" && self.value("active") == "0" })
        XCTAssertFalse(app.otherElements["nav-banner"].exists)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "browse chrome was not restored")
        XCTAssertEqual(value("idle"), "0")
        XCTAssertEqual(value("background"), "0")
        shot("nav-end")
        report("nav_end", "restored")
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
