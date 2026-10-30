import CoreGraphics
import XCTest

/// A11Y-W4: the accessibility and robustness sweep. Each case launches one surface at one
/// configuration, measures what the accessibility hierarchy exposes, and reports the numbers
/// instead of hiding them behind a screenshot. Required targets are the controls this lot owns;
/// a missing or undersized one fails the run. Truncation and clipping are reported as measured,
/// because XCUITest does not expose the rendered Text layout: a label ending in the ellipsis
/// character is the visible signal, and a frame outside the window is the clipped one.
///
/// The matrix covers Search, Settings, the transit board, transit detail and GO, the nav banner
/// and free driving at AX3 and AX5, in Arabic RTL, in dark mode and in landscape where it matters.
final class AccessibilitySuiteUITests: VelaUITestCase {
    private let ax3 = "UICTContentSizeCategoryAccessibilityXL"
    private let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"

    private var truncated = 0
    private var smallTargets = 0
    private var clippedTargets = 0
    private var cases = 0
    private var failures: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testAccessibilitySweepMatrix() {
        // Search: four configurations, the worst of them kept as a screenshot.
        searchCase("search_ax3", arguments: axArgument(ax3))
        searchCase("search_ax5", arguments: axArgument(ax5), screenshot: "a11y-search-ax5")
        searchCase("search_rtl", arguments: ["-VelaLanguage", "ar"], screenshot: "a11y-search-rtl")
        searchCase("search_dark_landscape", arguments: darkArguments, landscape: true,
                   screenshot: "a11y-search-dark-landscape")

        // Settings: the same four axes plus the RTL side of the Done button.
        settingsCase("settings_ax3", arguments: axArgument(ax3))
        settingsCase("settings_ax5", arguments: axArgument(ax5))
        settingsCase("settings_rtl", arguments: ["-VelaLanguage", "ar"],
                     screenshot: "a11y-settings-rtl")
        settingsCase("settings_dark_landscape", arguments: darkArguments, landscape: true,
                     screenshot: "a11y-settings-dark-landscape")

        // Transit board: AX3, AX5, and Arabic in dark mode.
        boardCase("transit_board_ax3", arguments: axArgument(ax3),
                  screenshot: "a11y-transit-ax3")
        boardCase("transit_board_ax5", arguments: axArgument(ax5))
        boardCase("transit_board_rtl_dark", arguments: ["-VelaLanguage", "ar"] + darkArguments)

        // Transit detail and GO: AX5 plus Arabic RTL.
        detailCase("transit_detail_ax5", arguments: axArgument(ax5),
                   screenshot: "a11y-transit-detail-ax5")
        detailCase("transit_detail_rtl", arguments: ["-VelaLanguage", "ar"])
        goCase("transit_go_ax5_dark", arguments: axArgument(ax5) + darkArguments,
               screenshot: "a11y-transit-go-ax5")
        goCase("transit_go_rtl", arguments: ["-VelaLanguage", "ar"])

        // Navigation: AX3, AX5, then dark Arabic.
        navCase("nav_ax3", arguments: axArgument(ax3))
        navCase("nav_ax5", arguments: axArgument(ax5))
        navCase("nav_dark_rtl", arguments: ["-VelaLanguage", "ar"] + darkArguments,
                screenshot: "a11y-nav-dark")

        // Free driving: AX5 in dark mode, then Arabic RTL.
        freeDriveCase("free_drive_ax5_dark", arguments: axArgument(ax5) + darkArguments,
                      screenshot: "a11y-free-drive-ax5")
        freeDriveCase("free_drive_rtl", arguments: ["-VelaLanguage", "ar"])

        report("a11y_truncated", truncated)
        report("a11y_small_targets", smallTargets)
        report("a11y_clipped_targets", clippedTargets)
        report("a11y_cases", cases)
        report("a11y_failures", failures.count)
        XCTAssertGreaterThanOrEqual(cases, 18, "the sweep did not reach every case")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: " | "))
    }

    // MARK: - Cases

    private func searchCase(_ name: String, arguments: [String], landscape: Bool = false,
                            screenshot: String? = nil) {
        let app = launch(camera: "sf", arguments: ["-VelaResetSettings", "YES"] + arguments)
        guard app.textFields["search-field"].exists else {
            fail("\(name): no map screen")
            return
        }
        search(app, query: "coffee")
        if app.buttons["search-clear"].waitForExistence(timeout: 10) == false {
            fail("\(name): the clear button is missing after a query")
        }
        // Search runs in portrait first: rotating before the keyboard settles left the field
        // above the window on the runner, which made XCUITest retry scroll-to-visible for minutes.
        if landscape { rotate() }
        measure(app, name: name, required: [
            "search-field", "search-clear", "map-overflow", "search-panel-toggle",
            "result-directions", "result-save",
        ], status: ["result-status"], sizeExempt: ["search-field"], screenshot: screenshot)
        if name.contains("rtl") {
            let placeholder = app.textFields["search-field"].placeholderValue as? String ?? ""
            report("a11y_search_rtl_placeholder", placeholder)
            let direction = app.windows.firstMatch.frame
            report("a11y_search_rtl_window", "\(Int(direction.width))x\(Int(direction.height))")
        }
    }

    private func settingsCase(_ name: String, arguments: [String], landscape: Bool = false,
                              screenshot: String? = nil) {
        let app = launch(camera: "sf", arguments: ["-VelaResetSettings", "YES"] + arguments)
        openSettings(app)
        guard app.descendants(matching: .any)["settings-screen"].waitForExistence(timeout: 20) else {
            fail("\(name): the settings screen did not open")
            return
        }
        if landscape { rotate() }
        measure(app, name: name, required: [
            "settings-done", "settings-language", "settings-units", "settings-clock",
        ], status: ["settings-debug"], screenshot: screenshot)
        if name.contains("rtl") {
            let done = app.buttons["settings-done"]
            if done.exists, done.frame.midX > app.frame.midX {
                fail("\(name): Done did not move to the RTL trailing edge")
            }
            report("a11y_settings_rtl_done", done.exists ? "trailing" : "missing")
        }
    }

    private func boardCase(_ name: String, arguments: [String], screenshot: String? = nil) {
        let app = launchRaw([
            "-VelaStartCamera", "sf", "-VelaDeterministic", "YES",
            "-VelaTransitBoardTest", "YES", "-VelaTransitBoardOfflineTest", "YES",
        ] + arguments)
        guard waitFor(app.descendants(matching: .any)["transit-board"], or: app.staticTexts["transit-board-station"],
                      timeout: 60) else {
            fail("\(name): the stop board did not open")
            return
        }
        _ = waitUntil(30) { self.boardValue(app, "loading") == "0" }
        measure(app, name: name, required: [
            "transit-board-close", "transit-board-refresh", "transit-board-station",
            "transit-board-line", "transit-board-departure",
        ], status: ["transit-board-offline"], screenshot: screenshot)
    }

    private func detailCase(_ name: String, arguments: [String], screenshot: String? = nil) {
        let app = launchRaw([
            "-VelaStartCamera", "sf", "-VelaDeterministic", "YES", "-VelaTransitFixture", "YES",
        ] + arguments)
        guard app.otherElements["transit-card"].waitForExistence(timeout: 60) else {
            fail("\(name): the transit fixture card did not open")
            return
        }
        let open = app.buttons["transit-detail-open"]
        guard open.waitForExistence(timeout: 15), open.isHittable else {
            fail("\(name): the detail entry is not reachable on the card")
            return
        }
        open.tap()
        guard app.descendants(matching: .any)["steps-sheet"].waitForExistence(timeout: 20) else {
            fail("\(name): the transit detail sheet did not open")
            return
        }
        measure(app, name: name, required: [
            "steps-close", "transit-trip-open", "transit-start",
        ], status: [], screenshot: screenshot)
    }

    private func goCase(_ name: String, arguments: [String], screenshot: String? = nil) {
        let app = launchRaw([
            "-VelaStartCamera", "sf", "-VelaDeterministic", "YES",
            "-VelaTransitGoTest", "YES", "-VelaTransitGoScene", "ride",
        ] + arguments)
        guard app.descendants(matching: .any)["transit-go-screen"].waitForExistence(timeout: 60) else {
            fail("\(name): the GO screen did not open")
            return
        }
        _ = waitUntil(20) { self.debugText("transit-go-debug") != nil }
        measure(app, name: name, required: [
            "transit-go-close", "transit-go-action", "transit-go-departures",
            "transit-go-later", "transit-go-trip", "transit-go-end",
        ], status: ["transit-go-time-status"], screenshot: screenshot)
    }

    private func navCase(_ name: String, arguments: [String], screenshot: String? = nil) {
        let app = startDrive(arguments: arguments)
        guard app.otherElements["nav-banner"].waitForExistence(timeout: 20) else {
            fail("\(name): the nav banner did not open")
            return
        }
        let banner = app.otherElements["nav-banner"]
        let fraction = banner.frame.height / app.windows.firstMatch.frame.height
        report("a11y_\(name)_banner_fraction", String(format: "%.2f", fraction))
        if fraction > 0.36 {
            fail("\(name): the turn card took \(Int(fraction * 100))% of the screen at this size")
        }
        measure(app, name: name, required: [
            "nav-banner", "nav-end", "nav-pause", "nav-voice", "nav-heading",
        ], status: ["nav-debug"], screenshot: screenshot)
    }

    private func freeDriveCase(_ name: String, arguments: [String], screenshot: String? = nil) {
        let app = startFreeDrive(arguments: arguments)
        guard app.descendants(matching: .any)["free-drive-chrome"].waitForExistence(timeout: 20) else {
            fail("\(name): the free-drive chrome did not open")
            return
        }
        measure(app, name: name, required: [
            "free-simple-map", "free-voice", "free-locate", "free-exit",
        ], status: ["free-debug"], screenshot: screenshot)
    }

    // MARK: - Navigation helpers

    private func openSettings(_ app: XCUIApplication) {
        let more = app.buttons["map-overflow"]
        guard more.waitForExistence(timeout: 30), more.isHittable else {
            fail("settings: the map menu is not reachable")
            return
        }
        more.tap()
        guard app.buttons["settings-menu-item"].waitForExistence(timeout: 10) else {
            fail("settings: the settings menu item is missing")
            return
        }
        app.buttons["settings-menu-item"].tap()
    }

    private func search(_ app: XCUIApplication, query: String) {
        let field = app.textFields["search-field"]
        guard field.exists, field.isHittable else {
            fail("search: the field is not reachable before typing")
            return
        }
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        }
        usleep(300_000)
        field.typeText(query + "\n")
        _ = app.buttons.matching(identifier: "search-result").firstMatch.waitForExistence(timeout: 60)
        sleep(2)
    }

    private func startDrive(arguments: [String]) -> XCUIApplication {
        let link = "https://www.google.com/maps/dir/?api=1" +
            "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving"
        let app = launch(camera: "sf", followUser: true, arguments: [
            "-VelaOpenURL", link, "-VelaNavBannerFixture", "YES",
        ] + arguments)
        let driveMode = app.buttons["route-mode-DRIVE"]
        if driveMode.waitForExistence(timeout: 30), routeValue(app, "mode") != "DRIVE" {
            driveMode.tap()
        }
        let start = app.buttons["route-start"]
        _ = waitUntil(180) { start.exists && start.isEnabled }
        guard start.exists, start.isEnabled, start.isHittable else {
            fail("nav: the Start button is not reachable on the runner")
            return app
        }
        start.tap()
        _ = waitUntil(30) { self.debugText("nav-debug")?.contains("nav=1") == true }
        return app
    }

    private func startFreeDrive(arguments: [String]) -> XCUIApplication {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaNavAlertsFixture", "YES"] + arguments)
        let open = app.buttons["free-drive-open"]
        guard open.waitForExistence(timeout: 60), open.isHittable else {
            fail("free drive: the entry button is not reachable")
            return app
        }
        open.tap()
        _ = waitUntil(30) { self.debugText("free-debug")?.contains("free=1") == true }
        return app
    }

    private func routeValue(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debugText("route-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func boardValue(_ app: XCUIApplication, _ key: String) -> String? {
        guard let line = debugText("transit-board-debug") else { return nil }
        for part in line.split(separator: " ") where part.hasPrefix("\(key)=") {
            return String(part.dropFirst(key.count + 1))
        }
        return nil
    }

    private func rotate() {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
    }

    private func launchRaw(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    // MARK: - Measurement

    /// Measures the visible hierarchy of one case and records the four required numbers. Contrast
    /// is reported as not measured: XCUITest exposes no rendered colour, so the contrast gate is
    /// the token pair in `DesignTokens.swift` and the dark-mode screenshots, not a frame query.
    private func measure(_ app: XCUIApplication, name: String, required: [String],
                         status: [String], sizeExempt: Set<String> = [],
                         screenshot: String?) {
        cases += 1
        let window = app.windows.firstMatch.frame
        let screen = window.insetBy(dx: -2, dy: -2)
        var caseTruncated = 0
        var caseSmall = 0
        var caseClipped = 0
        var caseColorOnly = 0

        for text in app.staticTexts.allElementsBoundByIndex {
            guard text.exists, text.frame.width > 1, text.frame.height > 1 else { continue }
            guard text.frame.intersects(window) else { continue }
            if text.label.contains("…") {
                caseTruncated += 1
                print("A11Y_TRUNCATED case=\(name) id=\(text.identifier) label=\(text.label)")
            }
            if !screen.contains(text.frame) {
                caseClipped += 1
                print("A11Y_CLIPPED case=\(name) text=\(text.identifier) frame=\(text.frame)")
            }
        }

        var interactive = app.buttons.allElementsBoundByIndex
            + app.switches.allElementsBoundByIndex
            + app.textFields.allElementsBoundByIndex
            + app.links.allElementsBoundByIndex
        interactive += app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", required)).allElementsBoundByIndex
        for element in interactive {
            guard element.exists, element.isEnabled else { continue }
            let frame = element.frame
            guard frame.width > 0, frame.height > 0, frame.intersects(window) else { continue }
            if frame.width < 44 || frame.height < 44 {
                caseSmall += 1
                print("A11Y_SMALL case=\(name) id=\(element.identifier) size=\(Int(frame.width))x\(Int(frame.height)) label=\(element.label)")
            }
            if !screen.contains(frame) {
                caseClipped += 1
                print("A11Y_CLIPPED case=\(name) id=\(element.identifier) frame=\(frame)")
            }
        }

        for id in required {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else {
                fail("\(name): required target missing: \(id)")
                continue
            }
            let frame = element.frame
            report("a11y_\(name)_target_\(key(id))", "\(Int(frame.width))x\(Int(frame.height))")
            if (frame.width < 44 || frame.height < 44) && !sizeExempt.contains(id) {
                fail("\(name): required target \(id) is \(Int(frame.width))x\(Int(frame.height))")
            }
        }

        for id in status {
            let element = app.descendants(matching: .any)[id].firstMatch
            guard element.exists else { continue }
            if element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                caseColorOnly += 1
                print("A11Y_COLOR_ONLY case=\(name) id=\(id)")
            }
        }

        truncated += caseTruncated
        smallTargets += caseSmall
        clippedTargets += caseClipped
        report("a11y_case_\(name)",
               "truncated=\(caseTruncated) small=\(caseSmall) clipped=\(caseClipped) "
               + "contrast=not-measured-xcuitest color_only=\(caseColorOnly)")
        if let screenshot { shot(screenshot) }
    }

    private func waitFor(_ first: XCUIElement, or second: XCUIElement, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if first.exists || second.exists { return true }
            usleep(500_000)
        }
        return first.exists || second.exists
    }

    private func fail(_ message: String) {
        failures.append(message)
        print("A11Y_FAIL \(message)")
    }


    private var darkArguments: [String] { ["-AppleInterfaceStyle", "Dark"] }

    private func key(_ id: String) -> String {
        id.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    private func axArgument(_ category: String) -> [String] {
        ["-UIPreferredContentSizeCategoryName", category]
    }
}
