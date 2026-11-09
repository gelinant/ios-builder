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

        // Manual controls remain possible: skip the final walk and reach done.
        app.buttons["transit-go-skip"].tap()
        XCTAssertTrue(waitUntil(10) { self.value(app, "go_step") == "transfer" },
                      "skipping the ride did not show the transfer walk")
        report("go_step", value(app, "go_step") ?? "?")
        app.buttons["transit-go-skip"].tap()
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

    /// GO-MAP: the San Francisco preview trip, riding the K one stop in, with the simulator at the
    /// San Francisco fixture point. The map frames the user and the alighting stop, draws the K
    /// shape and its two estimated vehicles, then refits on the next step and pauses on a pan.
    func testGoMapFramesUserAndTargetWithEstimatedVehicles() {
        let app = launch(scene: "map")
        let map = app.descendants(matching: .any)["transit-go-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 20), "the GO screen has no map")
        XCTAssertTrue(waitUntil(60) { self.mapValue(app, "go_map_style") == "1" },
                      "the GO map style never loaded")
        XCTAssertTrue(waitUntil(30) {
            self.mapValue(app, "go_map_fit") == "1" && self.mapValue(app, "go_map_user") == "1"
        }, "the user and the target are not both inside the map: \(mapLine(app))")
        XCTAssertTrue(waitUntil(15) { (Int(self.mapValue(app, "go_vehicles") ?? "") ?? 0) > 0 },
                      "no estimated vehicle on the GO map: \(mapLine(app))")
        XCTAssertEqual(mapValue(app, "go_map_target"), "alight")
        XCTAssertEqual(mapValue(app, "go_line"), "K")
        XCTAssertEqual(mapValue(app, "go_lines"), "1")
        XCTAssertEqual(mapValue(app, "go_vehicles_estimated"), "1")
        XCTAssertEqual(mapValue(app, "go_vehicle_hint"), "1")
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-map-estimated"].exists,
                      "the map does not say its vehicles are estimated")
        XCTAssertTrue(app.descendants(matching: .any)["transit-go-estimated"].exists,
                      "the rail does not follow the map's estimated vehicle")
        XCTAssertGreaterThan(map.frame.height, 200, "the map region is too small")
        report("go_map_fit", mapValue(app, "go_map_fit") ?? "?")
        report("go_map_user", mapValue(app, "go_map_user") ?? "?")
        report("go_map_target", mapValue(app, "go_map_target") ?? "?")
        report("go_vehicles", mapValue(app, "go_vehicles") ?? "?")
        report("go_lines", mapValue(app, "go_lines") ?? "?")
        report("go_dots", mapValue(app, "go_dots") ?? "?")
        report("go_web_errors", mapValue(app, "web_errors") ?? "?")
        report("go_web_error", mapValue(app, "web_error") ?? "?")
        shot("transit-go-map")

        // The next step: the final walk to the destination. The camera refits, the line goes.
        let refits = Int(mapValue(app, "go_map_refits") ?? "") ?? 0
        // The map takes the top of the screen: the manual controls are under the action card.
        let skip = app.buttons["transit-go-skip"]
        for _ in 0..<3 where !skip.isHittable {
            app.staticTexts["transit-go-action"].swipeUp()
        }
        skip.tap()
        XCTAssertTrue(waitUntil(10) { self.mapValue(app, "go_map_target") == "destination" },
                      "the map did not move to the destination step")
        XCTAssertTrue(waitUntil(10) {
            (Int(self.mapValue(app, "go_map_refits") ?? "") ?? 0) > refits
                && self.mapValue(app, "go_map_fit") == "1"
        }, "the camera did not refit on the new step: \(mapLine(app))")
        XCTAssertEqual(mapValue(app, "go_vehicles"), "0", "vehicles stayed after the ride")
        XCTAssertEqual(mapValue(app, "go_lines"), "0", "the line stayed after the ride")
        report("go_map_step_refit", 1)

        // A pan pauses the rule and shows Recenter; Recenter frames both points again.
        map.swipeLeft()
        XCTAssertTrue(waitUntil(5) { self.mapValue(app, "go_map_paused") == "1" },
                      "a pan did not pause the camera: \(mapLine(app))")
        let recenter = app.buttons["transit-go-map-recenter"]
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "no recenter control after a pan")
        XCTAssertGreaterThanOrEqual(recenter.frame.height, 44, "recenter is below 44 pt")
        recenter.tap()
        XCTAssertTrue(waitUntil(10) {
            self.mapValue(app, "go_map_paused") == "0" && self.mapValue(app, "go_map_fit") == "1"
        }, "recenter did not frame the user and the target: \(mapLine(app))")
        report("go_map_recenter", 1)
    }

    private func mapLine(_ app: XCUIApplication) -> String {
        debugText(app, "transit-go-map-debug") ?? "no map debug line"
    }

    private func mapValue(_ app: XCUIApplication, _ key: String) -> String? {
        field(debugText(app, "transit-go-map-debug"), key)
    }

    private func value(_ app: XCUIApplication, _ key: String) -> String? {
        field(debugText(app, "transit-go-debug"), key)
    }

    private func field(_ line: String?, _ key: String) -> String? {
        guard let line else { return nil }
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
