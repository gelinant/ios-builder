import XCTest

/// NAV-BANNER: lanes with the recommended ones highlighted, road shields, the step preview
/// behind a swipe, the current road line and per-stop figures. The shared route model carries
/// lanes and refs, but the fixture drive does not always have them, so the scenario opts into
/// `-VelaNavBannerFixture YES`; the store tests prove the same fields travel through `NavStore`.
final class NavBannerUITests: VelaUITestCase {
    private let fixtureDrive = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving"
    /// The stop case arrives as a shared link with one waypoint: the picker sheet is pinned to half
    /// the screen, so its "add stop" action can sit under the bottom edge and cannot be tapped.
    private let fixtureDriveWithStop = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving" +
        "&waypoints=37.7840,-122.4080"

    override func tearDown() {
        if let app, app.buttons["nav-end"].exists {
            app.buttons["nav-end"].tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 2) { confirm.tap() }
            _ = waitUntil(5) { self.value("activity") != "1" }
        }
        super.tearDown()
    }

    func testLanesShieldPreviewAndPerStopEta() throws {
        let app = startDrive(stop: true)
        let banner = app.otherElements["nav-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "no nav banner")

        let lanes = app.descendants(matching: .any)["nav-lanes"]
        XCTAssertTrue(lanes.waitForExistence(timeout: 10), "no lane diagram: \(debugText("nav-debug") ?? "none")")
        XCTAssertTrue(app.descendants(matching: .any)["nav-lane-3"].exists,
                      "the fixture's four lanes did not render")
        XCTAssertEqual(value("lanes"), "4", "the store did not publish four lanes")
        report("nav_banner_lanes", 4)

        let shield = app.descendants(matching: .any)["nav-shield"].firstMatch
        XCTAssertTrue(shield.waitForExistence(timeout: 10), "no road shield on the banner")
        report("nav_banner_shield", shield.label)
        XCTAssertTrue(app.descendants(matching: .any)["nav-current-road-shield"].exists,
                      "no persistent shield for the road under the car")
        XCTAssertTrue(app.staticTexts["nav-current-road"].exists, "no current road line")

        XCTAssertTrue(app.staticTexts["nav-next-stop"].waitForExistence(timeout: 10),
                      "no next stop line: \(debugText("nav-debug") ?? "none")")
        XCTAssertEqual(value("nextstop"), "1", "the drive lost its stop")
        XCTAssertTrue(app.staticTexts["nav-stop-eta"].exists, "no per-stop ETA")
        XCTAssertTrue(app.staticTexts["nav-stop-figures"].exists, "no per-stop distance and arrival clock")
        XCTAssertTrue(app.staticTexts["nav-trip"].exists, "no whole-trip line under the stop figures")
        report("nav_banner_stop_eta", app.staticTexts["nav-stop-eta"].label)
        report("nav_banner_trip", app.staticTexts["nav-trip"].label)
        shot("nav-banner-lanes-shield-stop")

        // A left swipe walks ahead without touching guidance; tapping the card restores live.
        banner.swipeLeft()
        let hint = app.staticTexts["nav-preview-hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5),
                      "the swipe did not open the step preview: \(debugText("nav-debug") ?? "none")")
        XCTAssertNotEqual(value("preview"), "-1", "the swipe did not move the previewed step")
        XCTAssertEqual(value("nav"), "1", "the swipe ended guidance")
        shot("nav-banner-preview")
        report("nav_banner_preview", value("preview") ?? "?")

        banner.tap()
        XCTAssertTrue(waitUntil(5) { !hint.exists }, "tapping the preview did not restore live guidance")
        XCTAssertEqual(value("preview"), "-1", "the preview index survived the tap")
        XCTAssertTrue(app.descendants(matching: .any)["nav-lanes"].exists, "live lanes left with the preview")
        shot("nav-banner-live-restored")
        report("nav_banner_restored", "1")
    }

    func testBannerAtAccessibilityXXXL() throws {
        let app = startDrive(stop: false, extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let banner = app.otherElements["nav-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "no nav banner at accessibility text")
        XCTAssertTrue(app.descendants(matching: .any)["nav-lanes"].waitForExistence(timeout: 10),
                      "the lane diagram vanished at large text")
        XCTAssertTrue(app.descendants(matching: .any)["nav-shield"].firstMatch.exists,
                      "the shield vanished at large text")
        // The card is measured with its instruction on it. The first AX run measured 0.11
        // because the maneuver text had not reached the banner yet: the card held the distance,
        // the lanes and the sign only. The drive takes longer to publish its first instruction
        // under the AX text size, so the text is awaited before any frame is read.
        XCTAssertTrue(waitUntil(60) { self.value("instr") == "1" },
                      "the card never received its maneuver text: \(debugText("nav-debug") ?? "none")")
        // Any element type: at AX XXXL SwiftUI publishes the enlarged text under a different
        // accessibility type, and a `staticTexts` query missed it while the card held it.
        let instruction = app.descendants(matching: .any)["nav-instruction"]
        XCTAssertTrue(instruction.waitForExistence(timeout: 10),
                      "the card shows no instruction at AX: \(debugText("nav-debug") ?? "none")")
        report("nav_banner_ax_instruction", instruction.label)
        let fraction = banner.frame.height / app.windows.firstMatch.frame.height
        report("nav_banner_ax_fraction", String(format: "%.2f", fraction))
        report("nav_banner_ax_heights", String(
            format: "banner=%.0f window=%.0f",
            banner.frame.height, app.windows.firstMatch.frame.height))
        XCTAssertLessThanOrEqual(fraction, 0.36,
                                 "the turn card took \(Int(fraction * 100))% of the screen at AX XXXL")
        shot("nav-banner-ax")
    }

    func testFrenchShieldStyles() throws {
        let app = startDrive(stop: false, extraArguments: ["-VelaShieldRegion", "FR"])
        let shield = app.descendants(matching: .any)["nav-shield"].firstMatch
        XCTAssertTrue(shield.waitForExistence(timeout: 10), "no French shield on the banner")
        XCTAssertEqual(shield.label, "A7")
        XCTAssertEqual(value("ref"), "A7", "the banner did not keep the route number")
        XCTAssertEqual(value("currentref"), "N7", "the current road lost its number")
        shot("nav-banner-shield-fr")
        report("nav_banner_shield_fr", shield.label)
    }

    func testUkShieldStyles() throws {
        let app = startDrive(stop: false, extraArguments: ["-VelaShieldRegion", "GB"])
        let shield = app.descendants(matching: .any)["nav-shield"].firstMatch
        XCTAssertTrue(shield.waitForExistence(timeout: 10), "no UK shield on the banner")
        XCTAssertEqual(shield.label, "M25")
        XCTAssertEqual(value("ref"), "M25", "the banner did not keep the route number")
        shot("nav-banner-shield-gb")
        report("nav_banner_shield_gb", shield.label)
    }

    /// Opens the link, waits for a driving route and starts it. With a stop, adds Embarcadero
    /// Station through R-1's picker first, so the bar has a real next stop and a real ETA.
    /// Scrolls the expanded picker, whichever element type carries the scroll container.
    private func scrollRoute(_ app: XCUIApplication) {
        // An existing scroll container can still be offscreen with an empty frame: swiping it
        // fails, so only a laid-out one is worth using.
        for candidate in [app.scrollViews["route-scroll"], app.otherElements["route-scroll"]]
        where candidate.exists && candidate.frame.height > 1 {
            candidate.swipeUp()
            return
        }
        app.otherElements["route-sheet"].swipeUp()
    }

    /// Expands the route picker: the compact presentation hides the stop and step actions.
    private func expandRoute(_ app: XCUIApplication) {
        guard !app.otherElements["route-expanded"].exists else { return }
        let toggle = app.buttons["route-expand"]
        guard toggle.waitForExistence(timeout: 10) else { return }
        toggle.tap()
        XCTAssertTrue(app.otherElements["route-expanded"].waitForExistence(timeout: 10),
                      "the route sheet did not expand")
    }

    private func startDrive(stop: Bool, extraArguments: [String] = []) -> XCUIApplication {
        let app = launch(
            camera: "sf",
            followUser: true,
            arguments: ["-VelaOpenURL", stop ? fixtureDriveWithStop : fixtureDrive,
                        "-VelaNavBannerFixture", "YES"] + extraArguments)
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

        if stop {
            // The waypoint comes from the shared link, so no picker interaction is needed.
            XCTAssertTrue(waitUntil(120) {
                self.routeValue("stops") == "1" && self.routeValue("loading") == "0"
                    && start.exists && start.isEnabled
            }, "the link's stop did not reach the route: \(debugText("route-debug") ?? "none")")
            report("nav_banner_stops", "1")
        }

        start.tap()
        // The banner is the surface under test, and at accessibility sizes the debug line can lag
        // the chrome by several seconds on a loaded runner; waiting on the banner removes that
        // flake without weakening the instruction assertion that follows.
        let banner = app.otherElements["nav-banner"]
        XCTAssertTrue(waitUntil(40) { banner.exists || self.value("nav") == "1" },
                      "navigation did not start")
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
