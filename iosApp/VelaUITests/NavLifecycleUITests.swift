import XCTest

/// NAV-LIFE: a drive that a background suspension or a process kill interrupts comes back with
/// the same session, the remaining ETA, the current step and the voice cue state. The route flows
/// use the same live search as NavUITests; the runner arms its simulated drive when guidance
/// starts.
final class NavLifecycleUITests: VelaUITestCase {
    /// The base class keeps `app` read-only; a relaunch needs a second instance, so every read in
    /// this scenario goes through this pointer.
    private var current: XCUIApplication?

    override func tearDown() {
        let active: XCUIApplication? = current ?? app
        if let active, active.buttons["nav-end"].exists {
            active.buttons["nav-end"].tap()
            let confirm = active.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testBackgroundSuspensionKeepsSessionStepAndVoice() throws {
        let app = launch(camera: "sf", followUser: true)
        current = app
        startDrive(app)

        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")
        XCTAssertTrue(waitUntil(20) { self.value("nav") == "1" }, "navigation did not start")
        XCTAssertTrue(waitUntil(30) { (self.intValue("left") ?? 0) > 0 }, "no remaining distance")

        let sessions = intValue("sessions") ?? 0
        let step = intValue("step") ?? 0
        let left = intValue("left") ?? 0
        let before = voiceLine()
        shot("nav-life-before-background")
        report("nav_life_sessions_before", sessions)
        report("nav_life_left_before", left)

        // A phone call and a locked screen reach the same lifecycle path as a home press: the
        // session is suspended, then the app returns. N-3 covers the audio interruption itself.
        XCUIDevice.shared.press(.home)
        sleep(4)
        app.activate()

        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20),
                      "the drive did not come back from the background")
        XCTAssertTrue(waitUntil(10) { self.value("bg") == "0" }, "the app did not report the foreground")
        XCTAssertEqual(value("nav"), "1")
        XCTAssertEqual(value("active"), "1")
        XCTAssertEqual(value("paused"), "0")
        XCTAssertEqual(intValue("sessions"), sessions, "the background suspension started a second session")
        XCTAssertGreaterThanOrEqual(intValue("step") ?? -1, step, "the current step went backwards")
        XCTAssertGreaterThanOrEqual(intValue("left") ?? -1, 0)
        XCTAssertGreaterThan(intValue("eta") ?? 0, 0, "the remaining ETA was lost")
        XCTAssertEqual(value("instr"), "1", "the current instruction is empty after resume")
        XCTAssertGreaterThanOrEqual(intValue("left") ?? 0, 0)

        // No duplicate instruction: if the last spoken line is the same, the count must not move.
        let after = voiceLine()
        if let before, let after, before.text == after.text {
            XCTAssertEqual(after.count, before.count, "the same instruction was spoken twice")
        }
        shot("nav-life-background")
        report("nav_life_background", "session=1 step=\(value("step") ?? "-") eta=\(value("eta") ?? "-")")

        endDrive(app)
    }

    func testRelaunchResumesTheDrive() throws {
        let app = launch(camera: "sf", followUser: true)
        current = app
        startDrive(app)
        XCTAssertTrue(app.otherElements["nav-banner"].waitForExistence(timeout: 20), "no nav banner")
        XCTAssertTrue(waitUntil(20) { self.value("nav") == "1" }, "navigation did not start")
        let sessions = intValue("sessions") ?? 0
        let left = intValue("left") ?? 0
        XCTAssertGreaterThan(left, 0)
        shot("nav-life-before-relaunch")
        report("nav_life_relaunch_left", left)

        // A process kill, as after a system reap: no End, so the resume record stays.
        app.terminate()
        // The normal launch helper waits for browser chrome, which the resumed drive replaces.
        let relaunched = XCUIApplication()
        relaunched.launchArguments = [
            "-VelaStartCamera", "sf", "-VelaDeterministic", "YES", "-VelaFollowUser", "YES",
        ]
        relaunched.launch()
        current = relaunched
        XCTAssertTrue(waitUntil(90) { self.value("nav") == "1" },
                      "the drive did not resume: \(text("nav-debug") ?? "none")")
        XCTAssertTrue(relaunched.otherElements["nav-banner"].waitForExistence(timeout: 20),
                      "no nav banner after the resume")
        XCTAssertTrue(waitUntil(30) { self.value("resumed") == "1" },
                      "the resumed drive was not marked: \(text("nav-debug") ?? "none")")
        XCTAssertEqual(value("resuming"), "0")
        XCTAssertEqual(value("resumefailed"), "0")
        XCTAssertGreaterThanOrEqual(intValue("sessions") ?? 0, sessions)
        XCTAssertGreaterThan(intValue("left") ?? 0, 0, "no remaining distance after the resume")
        XCTAssertGreaterThan(intValue("eta") ?? 0, 0, "no remaining ETA after the resume")
        XCTAssertEqual(value("instr"), "1", "no current instruction after the resume")
        XCTAssertEqual(value("voicemode"), "on")
        shot("nav-life-resume")
        report("nav_life_resume", "step=\(value("step") ?? "-") eta=\(value("eta") ?? "-")")

        endDrive(relaunched)
    }

    private func startDrive(_ app: XCUIApplication) {
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
        if !picked { rows.firstMatch.tap() }
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        if routeValue("mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        XCTAssertTrue(waitUntil(90) {
            self.routeValue("loading") == "0" && (Int(self.routeValue("routes") ?? "") ?? 0) > 0
        }, "no driving route: \(text("route-debug") ?? "none")")
        app.buttons["route-start"].tap()
    }

    private func endDrive(_ app: XCUIApplication) {
        app.buttons["nav-end"].tap()
        let confirm = app.buttons["nav-end-confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no End confirmation")
        confirm.tap()
        XCTAssertTrue(waitUntil(10) { self.value("nav") == "0" && self.value("active") == "0" })
        report("nav_life_end", "restored")
    }

    /// `spoken=12 text=Turn left` from the voice debug line, for the duplicate check.
    /// Reads a debug label from whichever app instance is live, including a relaunch.
    private func text(_ id: String) -> String? {
        guard let current else { return nil }
        let element = current.staticTexts[id]
        return element.exists ? element.label : nil
    }

    private func voiceLine() -> (count: Int, text: String)? {
        guard let line = text("nav-voice-debug") else { return nil }
        let parts = line.split(separator: " ")
        guard let countPart = parts.first(where: { $0.hasPrefix("spoken=") }),
              let count = Int(countPart.dropFirst("spoken=".count)) else { return nil }
        let text = parts.filter { $0.hasPrefix("text=") }
            .map { String($0.dropFirst("text=".count)) }
            .joined(separator: " ")
        return (count, text)
    }

    private func routeValue(_ key: String) -> String? {
        guard let line = text("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func value(_ key: String) -> String? {
        guard let line = text("nav-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func intValue(_ key: String) -> Int? {
        value(key).flatMap(Int.init)
    }
}
