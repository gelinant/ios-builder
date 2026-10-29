import XCTest

/// SRCH-CMD: the same commands typed and spoken. Home, Work and directions read the saved
/// shortcuts and the ordinary search; along-the-route reads a fixed Debug route and keeps only
/// places in its corridor; call reads the address book only when asked and explains a refusal.
/// A phrase the parser does not know stays an ordinary search. Each step reports the command kind
/// the app actually published, not the one the test expected.
final class SearchCommandUITests: VelaUITestCase {
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
        // The kind is published before the search runs, so read it before the chooser and the
        // place card cover the debug block (MapScreen hides that block while a card is open).
        XCTAssertTrue(waitUntil(10) {
            (self.debugValues(app)["cmd_kind"] ?? "") == "directions"
        }, "directions was not classified: \(debugText("search-debug") ?? "none")")
        reportKind(app, "directions")
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 90),
                      "directions did not open the route chooser")
        XCTAssertTrue(app.staticTexts["route-destination"].waitForExistence(timeout: 10),
                      "directions opened without a destination")
        closeRoute(app)
        // The first result stays open behind the chooser; close it so the field and the debug
        // block are reachable again for the next command.
        let placeClose = app.buttons["place-close"]
        if placeClose.waitForExistence(timeout: 5) { placeClose.tap() }
        sleep(1)

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

    /// Types the phrase, waits for the field to hold every character, then presses Return on its
    /// own. The commit is what the command parser reads, so the scenario never races it. The field
    /// is emptied with Delete keys rather than the clear button, whose position follows the panel
    /// layout and can sit outside the screen while the field itself is still reachable.
    private func typed(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["search-field"]
        field.tap()
        let current = (field.value as? String) ?? ""
        if !current.isEmpty && current != "Search" {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        XCTAssertTrue(waitUntil(5) { (field.value as? String) == text },
                      "the field did not hold \(text): \(field.value ?? "empty")")
        field.typeText("\n")
    }

    private func closeRoute(_ app: XCUIApplication) {
        let close = app.buttons["route-close"]
        if close.waitForExistence(timeout: 10) { close.tap() }
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
        let line = app.staticTexts["search-debug"].exists
            ? app.staticTexts["search-debug"].label : ""
        var out: [String: String] = [:]
        for word in line.split(separator: " ") {
            let parts = word.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }
}
