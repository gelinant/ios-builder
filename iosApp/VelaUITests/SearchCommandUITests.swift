import XCTest

/// SRCH-CMD: the same commands typed and spoken. Home, Work and directions read the saved
/// shortcuts and the ordinary search; along-the-route reads a fixed Debug route and keeps only
/// places in its corridor; call reads the address book only when asked and explains a refusal.
/// A phrase the parser does not know stays an ordinary search. Each step reports the command kind
/// the app actually published, not the one the test expected.
final class SearchCommandUITests: VelaUITestCase {
    /// The Market Street drive the host replay follows, with both ends on the fixture.
    private let fixtureDrive = "https://www.google.com/maps/dir/?api=1" +
        "&origin=37.7749,-122.4194&destination=37.7942,-122.3946&travelmode=driving"

    override func tearDown() {
        if let app { endDrive(app) }
        super.tearDown()
    }

    func testTypedAndSpokenCommands() throws {
        let app = launch(
            camera: "sf",
            arguments: [
                "-VelaIntentTestReset", "YES",
                "-VelaSearchCommandFixture", "YES",
                "-VelaContactsPermission", "denied",
            ])
        sleep(6)

        // Home and Work come from the fixture, so the chooser must name that saved place. Neither
        // command may cost a search request.
        typed(app, "home")
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 45),
                      "home did not open the route chooser: \(debugText("search-debug") ?? "none")")
        XCTAssertTrue(app.staticTexts["route-destination"].waitForExistence(timeout: 10),
                      "the route chooser has no destination: \(debugText("search-debug") ?? "none")")
        XCTAssertTrue(app.staticTexts["route-destination"].label.contains("Ferry Building"),
                      "home did not use the saved Home: \(app.staticTexts["route-destination"].label)")
        shot("search-command")
        // The chooser covers the debug labels, so read them once it is closed again.
        closeRoute(app)
        reportKind(app, "home")
        let homeValues = debugValues(app)
        XCTAssertEqual(homeValues["searches"], "0", "home cost a search request")
        report("cmd_searches", homeValues["searches"] ?? "none")

        typed(app, "work")
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 45),
                      "work did not open the route chooser: \(debugText("search-debug") ?? "none")")
        XCTAssertTrue(app.staticTexts["route-destination"].waitForExistence(timeout: 10),
                      "the route chooser has no destination: \(debugText("search-debug") ?? "none")")
        XCTAssertTrue(app.staticTexts["route-destination"].label.contains("Salesforce Tower"),
                      "work did not use the saved Work: \(app.staticTexts["route-destination"].label)")
        closeRoute(app)
        reportKind(app, "work")
        let workValues = debugValues(app)
        XCTAssertEqual(workValues["searches"], "0", "work cost a search request")
        report("cmd_searches", workValues["searches"] ?? "none")

        typed(app, "directions to coffee")
        // The chooser can cover the debug block before the first poll, and a missing block reads
        // as no command at all. Wait for the chooser itself, then read the kind once the block is
        // reachable again: the command kind is published before the search runs and persists.
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 90),
                      "directions did not open the route chooser: \(debugText("search-debug") ?? "none")")
        XCTAssertTrue(app.staticTexts["route-destination"].waitForExistence(timeout: 10),
                      "directions opened without a destination")
        closeRoute(app)
        // The first result stays open behind the chooser; close it so the field and the debug
        // block are reachable again for the next command.
        let placeClose = app.buttons["place-close"]
        if placeClose.waitForExistence(timeout: 5) { placeClose.tap() }
        sleep(1)
        reportKind(app, "directions")

        typed(app, "search along the route coffee")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 90),
                      "along route returned no row: \(debugText("search-debug") ?? "none")")
        let along = debugValues(app)
        XCTAssertTrue((along["cmd_found"] ?? "0") != "0", "the corridor kept nothing")
        reportKind(app, "along")
        report("cmd_corridor_m", along["cmd_corridor_m"] ?? "none")
        report("cmd_found", along["cmd_found"] ?? "none")
        shot("search-along-route")

        typed(app, "call Ada Lovelace")
        XCTAssertTrue(waitUntil(20) {
            (self.debugValues(app)["cmd_kind"] ?? "") == "call"
                && (self.debugValues(app)["cmd_contacts"] ?? "") == "denied"
        }, "call did not report the refusal: \(debugText("search-debug") ?? "none")")
        reportKind(app, "call")
        report("cmd_contacts", debugValues(app)["cmd_contacts"] ?? "none")

        // Anything the parser does not know keeps the plain search path.
        typed(app, "coffee")
        XCTAssertTrue(waitUntil(90) {
            let now = self.debugValues(app)
            return (now["cmd_kind"] ?? "") == "-" && (now["cmd_len"] ?? "0") == "6"
                && (now["results"] ?? "0") != "0"
        }, "an unrecognised phrase did not run a plain search: \(debugText("search-debug") ?? "none")")
        reportKind(app, "-")
        report("cmd_searches", debugValues(app)["searches"] ?? "none")

        app.terminate()

        let spoken = launch(
            camera: "sf",
            arguments: [
                "-VelaContactsPermission", "granted",
                "-VelaContactsFixture", "Ada Lovelace|+14155550100",
                "-VelaVoiceQuery", "call Ada Lovelace",
            ])
        sleep(4)
        let mic = spoken.buttons["voice-search"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "no voice search button")
        mic.tap()
        XCTAssertTrue(waitUntil(45) {
            (self.debugValues(spoken)["cmd_kind"] ?? "") == "call"
                && (self.debugValues(spoken)["cmd_contacts"] ?? "") == "granted"
        }, "the dictated call did not use the same parser: \(debugText("search-debug") ?? "none")")
        reportKind(spoken, "call")
        report("cmd_contacts", debugValues(spoken)["cmd_contacts"] ?? "none")
    }

    /// SRCH-ALONG: during a drive the corridor starts at the car, not at the origin. The drive
    /// chrome replaces the browser chrome, and with it the search field, so the command fixture
    /// submits "coffee along the route" itself once the car has moved 600 m. The drive is then
    /// ended so the browser chrome, and the search debug line, come back for the assertion.
    func testAlongRouteSkipsTheTravelledPart() throws {
        let app = launch(
            camera: "sf", followUser: true,
            arguments: [
                "-VelaOpenURL", fixtureDrive,
                "-VelaSearchCommandFixture", "YES",
            ])
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "the directions link did not open the chooser")
        if routeValue(app, "mode") != "DRIVE" {
            app.buttons["route-mode-DRIVE"].tap()
        }
        let start = app.buttons["route-start"]
        XCTAssertTrue(waitUntil(120) { start.exists && start.isEnabled },
                      "no driving route: \(debugText("route-debug") ?? "none")")
        start.tap()
        XCTAssertTrue(waitUntil(20) { self.navValue(app, "nav") == "1" },
                      "navigation did not start")
        guard let full = navInt(app, "left") else {
            return XCTFail("the drive published no route length")
        }
        // The host arms the sf-market replay on "nav replay: start". The Debug hook submits the
        // command once 600 m are behind the car; wait for that, then give the ordinary place
        // search the network time it needs before the corridor pass can run.
        XCTAssertTrue(waitUntil(90) { (self.navInt(app, "left") ?? full) <= full - 600 },
                      "the simulated drive did not advance: \(debugText("nav-debug") ?? "none")")
        let leftBeforeCommand = navInt(app, "left") ?? full
        sleep(35)
        endDrive(app)
        XCTAssertTrue(waitUntil(30) { !app.otherElements["nav-banner"].exists },
                      "the drive did not end: \(debugText("nav-debug") ?? "none")")
        // Closing the chooser brings the debug block back over the map.
        let routeClose = app.buttons["route-close"]
        if routeClose.waitForExistence(timeout: 10) { routeClose.tap() }
        XCTAssertTrue(waitUntil(90) {
            let values = self.debugValues(app)
            return (values["cmd_kind"] ?? "") == "along"
                && (Int(values["cmd_route_m"] ?? "") ?? 0) > 0
        }, "the along command did not publish its corridor: \(debugText("search-debug") ?? "none")")
        let along = debugValues(app)
        XCTAssertEqual(along["cmd_from"], "progress",
                       "the corridor did not start at the car: \(debugText("search-debug") ?? "none")")
        let used = Int(along["cmd_route_m"] ?? "") ?? 0
        XCTAssertGreaterThan(used, 0, "the corridor ran on no route")
        XCTAssertLessThanOrEqual(used, full - 400,
                                 "the corridor still used the whole route (\(used) of \(full) m)")
        report("cmd_hook", along["cmd_hook"] ?? "none")
        report("cmd_from", along["cmd_from"] ?? "none")
        report("cmd_route_m", used)
        report("cmd_route_full_m", full)
        report("cmd_route_left_at_command", leftBeforeCommand)
        report("cmd_corridor_m", along["cmd_corridor_m"] ?? "none")
        report("cmd_found", along["cmd_found"] ?? "none")
        shot("search-along-progress")
    }

    /// Types the phrase, waits for the field to hold every character, then presses Return on its
    /// own. The commit is what the command parser reads, so the scenario never races it. The field
    /// is emptied with Delete keys rather than the clear button, whose position follows the panel
    /// layout and can sit outside the screen while the field itself is still reachable.
    private func typed(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["search-field"]
        focus(field, app)
        // Clear first: a plain text replacement leaves the caret where the tap landed, and a
        // backspace run from the middle of the previous phrase keeps its tail. The field's own
        // clear button resets both the text and the caret; when it is off screen, put the caret
        // after the text and delete a bounded run instead.
        let clear = app.buttons["search-clear"]
        if clear.exists && clear.isHittable {
            clear.tap()
            focus(field, app)
        } else {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 80))
        }
        field.typeText(text)
        XCTAssertTrue(waitUntil(5) { (field.value as? String) == text },
                      "the field did not hold \(text): \(field.value ?? "empty")")
        field.typeText("\n")
    }

    /// Taps the field until the keyboard is up: a tap sent while the previous sheet is still
    /// dismissing can be swallowed, and the next typeText then fails for lack of focus.
    private func focus(_ field: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { return }
            sleep(1)
        }
    }

    /// Ends a drive and confirms, retrying once if the confirmation tap did not land. The banner
    /// is the evidence: while it is gone the browser chrome, and the debug block, are back.
    private func endDrive(_ app: XCUIApplication) {
        for _ in 0..<2 {
            let end = app.buttons["nav-end"]
            guard end.exists else { return }
            end.tap()
            let confirm = app.buttons["nav-end-confirm"].firstMatch
            if confirm.waitForExistence(timeout: 5) { confirm.tap() }
            if waitUntil(10, { !app.otherElements["nav-banner"].exists }) { return }
        }
    }

    private func closeRoute(_ app: XCUIApplication) {
        let close = app.buttons["route-close"]
        if close.waitForExistence(timeout: 10) {
            close.tap()
            // Do not hand the next tap to a sheet that is still on its way out.
            _ = waitUntil(10) { !app.otherElements["route-sheet"].exists }
        }
        sleep(1)
    }

    /// Reports and checks the kind the app published, so a line proves the classification.
    private func reportKind(_ app: XCUIApplication, _ expected: String) {
        XCTAssertTrue(app.staticTexts["search-debug"].waitForExistence(timeout: 10),
                      "no search-debug line after the command")
        let values = debugValues(app)
        report("cmd_kind", values["cmd_kind"] ?? "none")
        XCTAssertEqual(values["cmd_kind"], expected,
                       "wrong command kind: \(debugText("search-debug") ?? "none")")
        report("cmd_len", values["cmd_len"] ?? "none")
    }

    /// The Debug status line as key/value pairs, so a report can name the corridor and contacts
    /// state without parsing prose.
    private func debugValues(_ app: XCUIApplication) -> [String: String] {
        values(app, id: "search-debug")
    }

    private func values(_ app: XCUIApplication, id: String) -> [String: String] {
        let line = app.staticTexts[id].exists ? app.staticTexts[id].label : ""
        var out: [String: String] = [:]
        for word in line.split(separator: " ") {
            let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }

    private func navValue(_ app: XCUIApplication, _ key: String) -> String? {
        values(app, id: "nav-debug")[key]
    }

    private func navInt(_ app: XCUIApplication, _ key: String) -> Int? {
        navValue(app, key).flatMap(Int.init)
    }

    private func routeValue(_ app: XCUIApplication, _ key: String) -> String? {
        values(app, id: "route-debug")[key]
    }
}
