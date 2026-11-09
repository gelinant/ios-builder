import XCTest

/// TRANSIT-GO: one current action, the live countdown, the remaining-stops rail, the get-off cue
/// and the four bottom controls. The Debug host presents the screen on the M2 Paris fixture, so
/// no planner and no network are involved; the same assertions read the screen's debug line.
final class TransitGoUITests: VelaUITestCase {
    private func launch(scene: String = "ride", degraded: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitGoTest", "YES",
            "-VelaTransitGoScene", scene,
        ]
        if degraded {
            app.launchArguments.append("-VelaTransitGoDegraded")
        }
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 60),
                      "the GO screen was not presented")
        return app
    }

    func testGoModeCuesAndRail() {
        let app = launch()
        XCTAssertTrue(waitUntil(15) { self.value(app, "go_step") != nil }, "no GO debug line")

        // The ride: one huge action, a coloured line badge, the rail and an estimated position.
        XCTAssertTrue(app.staticTexts["transit-go-action"].exists, "no current action")
        XCTAssertTrue(app.staticTexts["transit-go-action"].label.contains("Belleville"),
                      "the ride action does not name the alight stop")
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-time-status"].exists,
                      "no live/scheduled mark")
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-estimated"].exists,
                      "no estimated position on the rail")
        shot("transit-go-ride")
        XCTAssertTrue(app.buttons["transit-go-departures"].exists, "no next-departures control")
        XCTAssertTrue(app.buttons["transit-go-later"].exists, "no leave-later control")
        XCTAssertTrue(app.buttons["transit-go-trip"].exists, "no whole-trip control")
        XCTAssertTrue(app.buttons["transit-go-end"].exists, "no end control")
        for identifier in ["transit-go-departures", "transit-go-later", "transit-go-trip", "transit-go-end"] {
            XCTAssertGreaterThanOrEqual(app.buttons[identifier].frame.height, 44,
                                        "\(identifier) is below 44 pt")
        }
        let step = value(app, "go_step") ?? "?"
        let estimated = value(app, "go_estimated") ?? "?"
        let cue = value(app, "go_cue") ?? "?"
        report("go_step", step)
        report("go_estimated", estimated)
        report("go_cue", cue)
        XCTAssertEqual(step, "ride")
        XCTAssertEqual(estimated, "1", "the live fixture did not expose an estimate")
        XCTAssertEqual(cue, "none", "the get-off cue fired too early")

        // One stop later: the get-off cue, with its text and its accessibility label.
        app.buttons["transit-go-advance"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_cue") == "stop" },
                      "the get-off cue did not fire at the stop")
        let cueElement = app.descendants(matching: .any)["transit-go-cue"]
        XCTAssertTrue(cueElement.exists, "no visible get-off cue banner")
        XCTAssertTrue(cueElement.label.contains("Get off"),
                      "the cue is not readable without colour")
        XCTAssertTrue(app.staticTexts["transit-go-action"].label.contains("Get off now"),
                      "the current action did not switch to the alight")
        report("go_cue", value(app, "go_cue") ?? "?")
        report("go_step", value(app, "go_step") ?? "?")
        shot("transit-go-getoff")

        // Manual controls remain possible: Next leaves the ride, then reaches done.
        app.buttons["transit-go-next"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_step") == "transfer" },
                      "skipping the ride did not show the transfer walk")
        report("go_step", value(app, "go_step") ?? "?")
        app.buttons["transit-go-next"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_step") == "done" },
                      "the trip did not finish")
        report("go_step", value(app, "go_step") ?? "?")

        // Degraded: no live data and no network. Scheduled everywhere, no estimate, no fake cue.
        app.terminate()
        let offline = launch(degraded: true)
        XCTAssertTrue(waitUntil(15) { self.value(offline, "go_step") != nil }, "no degraded debug line")
        XCTAssertTrue(offline.descendants(matching: .any)["transit-go-offline"].exists,
                      "the offline state is not stated")
        XCTAssertFalse(offline.descendants(matching: .any)["transit-go-estimated"].exists,
                       "a degraded plan showed an estimated position")
        XCTAssertEqual(value(offline, "go_estimated"), "0", "a degraded plan claimed an estimate")
        XCTAssertEqual(value(offline, "go_cue"), "none", "a degraded plan announced a cue")
        XCTAssertEqual(value(offline, "go_step"), "ride")
        report("go_estimated", value(offline, "go_estimated") ?? "?")
        report("go_cue", value(offline, "go_cue") ?? "?")
        report("transit_go_degraded", "offline=1")
        shot("transit-go-degraded")
    }

    /// GO's Leave later follows the trip screen's anchor rule: the stop board's own departure for
    /// this run, or now plus the minutes with a notice when the board has no time for the stop.
    func testLeaveLaterAnchorsOnTheBoardOrSaysItCannot() {
        let boardApp = launch(scene: "anchor")
        XCTAssertTrue(waitUntil(15) { self.value(boardApp, "go_step") != nil }, "no GO debug line")
        boardApp.buttons["transit-go-later"].tap()
        let fifteen = boardApp.buttons["transit-go-later-15"].firstMatch
        XCTAssertTrue(fifteen.waitForExistence(timeout: 10), "no +15 choice")
        fifteen.tap()
        XCTAssertTrue(waitUntil(10) { self.value(boardApp, "go_anchor") == "board" },
                      "GO did not anchor on the board's own departure")
        XCTAssertEqual(value(boardApp, "go_fallback_notice"), "0")
        XCTAssertFalse(boardApp.descendants(matching: .any)["transit-go-anchor-notice"].exists,
                       "a board anchor showed the fallback notice")
        report("go_anchor", value(boardApp, "go_anchor") ?? "?")
        report("go_fallback_notice", value(boardApp, "go_fallback_notice") ?? "?")
        shot("transit-go-anchor")
        boardApp.terminate()

        // The board answers for the stop but has no departure for this run: now plus N, said out loud.
        let fallbackApp = launch(scene: "fallback")
        XCTAssertTrue(waitUntil(15) { self.value(fallbackApp, "go_step") != nil }, "no GO debug line")
        fallbackApp.buttons["transit-go-later"].tap()
        let later = fallbackApp.buttons["transit-go-later-15"].firstMatch
        XCTAssertTrue(later.waitForExistence(timeout: 10), "no +15 choice")
        later.tap()
        XCTAssertTrue(waitUntil(10) { self.value(fallbackApp, "go_anchor") == "now" },
                      "GO did not fall back to now when the board had no departure")
        XCTAssertEqual(value(fallbackApp, "go_fallback_notice"), "1")
        let notice = fallbackApp.descendants(matching: .any)["transit-go-anchor-notice"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "the fallback is not stated on screen")
        XCTAssertTrue(notice.label.contains("no departure time"),
                      "the notice does not say why the board was not used")
        report("go_anchor", value(fallbackApp, "go_anchor") ?? "?")
        report("go_fallback_notice", value(fallbackApp, "go_fallback_notice") ?? "?")
        shot("transit-go-fallback")
    }

    /// GO-STEPS: Previous and Next walk the steps both ways, are disabled at the ends, name their
    /// target for VoiceOver, hold against the older position and never replay a played cue.
    func testPreviousAndNextStepThroughTheTrip() {
        let app = launch()
        XCTAssertTrue(waitUntil(15) { self.value(app, "go_step") == "ride" }, "GO did not start on the ride")
        let previous = app.buttons["transit-go-previous"]
        let next = app.buttons["transit-go-next"]
        XCTAssertTrue(previous.exists && next.exists, "no Previous or Next")
        XCTAssertGreaterThanOrEqual(previous.frame.height, 44, "Previous is below 44 pt")
        XCTAssertGreaterThanOrEqual(next.frame.height, 44, "Next is below 44 pt")
        XCTAssertTrue(previous.label.contains("Take M2"), "Previous does not name its step: \(previous.label)")
        XCTAssertTrue(next.label.contains("Transfer"), "Next does not name its step: \(next.label)")
        report("go_step_previous_label", previous.label)
        report("go_step", value(app, "go_step") ?? "?")

        previous.tap()
        XCTAssertTrue(waitUntil(10) {
            self.value(app, "go_step") == "walk" && self.value(app, "go_leg") == "1"
        }, "Previous did not go back to the wait")
        XCTAssertEqual(value(app, "go_held"), "1", "the manual step is not held")
        report("go_step", "wait")
        report("go_held", value(app, "go_held") ?? "?")
        previous.tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_leg") == "0" }, "Previous did not reach the walk")
        XCTAssertEqual(value(app, "go_prev"), "0")
        XCTAssertFalse(previous.isEnabled, "Previous stays enabled at the first step")
        report("go_step", value(app, "go_step") ?? "?")
        shot("transit-go-steps-first")

        next.tap()
        next.tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_step") == "ride" }, "Next did not return to the ride")
        XCTAssertEqual(value(app, "go_held"), "0", "Next back to the step did not end the hold")
        report("go_step", "ride")
        app.buttons["transit-go-advance"].tap()
        app.buttons["transit-go-advance"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_cue_at") == "stop" }, "no stop cue")
        let cues = value(app, "go_cues") ?? "?"

        next.tap()
        previous.tap()
        app.buttons["transit-go-advance"].tap()
        app.buttons["transit-go-advance"].tap()
        XCTAssertTrue(waitUntil(5) { self.value(app, "go_stops") == "0" }, "the ride did not reach its stop")
        XCTAssertEqual(value(app, "go_cues"), cues, "a played cue replayed after Previous and Next")
        report("go_cues_replayed", value(app, "go_cues") == cues ? "0" : "1")

        next.tap()
        next.tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_step") == "done" }, "Next did not finish the trip")
        XCTAssertEqual(value(app, "go_next"), "0")
        XCTAssertFalse(next.isEnabled, "Next stays enabled at done")
        report("go_step", "done")
        previous.tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_step") == "transfer" }, "Previous from done failed")
        report("go_step", value(app, "go_step") ?? "?")
        shot("transit-go-steps")
    }

    /// GO-STEPS: a GO step moves the shared session, which updates the Live Activity when the host
    /// allows ActivityKit. The recorded San Francisco trip runs without location fixes.
    func testGoStepsMoveTheSessionAndItsActivity() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-VelaStartCamera", "sf",
            "-VelaDeterministic", "YES",
            "-VelaTransitFixture", "YES",
        ]
        app.launch()
        let open = app.buttons["transit-go-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 30), "no GO button on the transit card")
        open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 20),
                      "GO did not open")
        XCTAssertTrue(waitUntil(15) { self.value(app, "session_leg") == "0" }, "GO does not see the session")
        let updates = Int(value(app, "actupdates") ?? "0") ?? 0
        let checksActivity = value(app, "actenabled") == "1"

        app.buttons["transit-go-next"].tap()
        app.buttons["transit-go-next"].tap()
        XCTAssertTrue(waitUntil(10) {
            self.value(app, "session_leg") == "1" && self.value(app, "session_boarded") == "1"
                && self.value(app, "go_step") == "ride"
        }, "the session did not follow GO's Next")
        report("go_session", "leg=1 boarded=1")
        if checksActivity {
            XCTAssertTrue(waitUntil(5) { (Int(self.value(app, "actupdates") ?? "0") ?? 0) > updates },
                          "the step did not update the Live Activity")
        }

        app.buttons["transit-go-previous"].tap()
        XCTAssertTrue(waitUntil(10) {
            self.value(app, "session_boarded") == "0" && self.value(app, "go_held") == "1"
        }, "the session did not follow GO's Previous")
        XCTAssertEqual(value(app, "session_leg"), "1")
        XCTAssertEqual(value(app, "go_leg"), "1")
        report("go_session", "leg=1 boarded=0")
        report("go_activity", checksActivity ? "updates=\(value(app, "actupdates") ?? "?")" : "unsupported_or_disabled")
        shot("transit-go-steps-session")
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debugText(app, "transit-go-debug") else { return nil }
        for field in line.split(separator: " ") {
            let parts = field.split(separator: "=", maxSplits: 1)
            if parts.count == 2, parts[0] == Substring(key) {
                return String(parts[1])
            }
        }
        return nil
    }

    private func debugText(_ app: XCUIApplication, _ identifier: String) -> String? {
        let element = app.staticTexts[identifier]
        return element.exists ? element.label : nil
    }
}
