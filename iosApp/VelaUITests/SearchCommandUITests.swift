import XCTest

/// SRCH-CMD: the same commands typed and spoken. Home, Work and directions read the saved
/// shortcuts and the ordinary search; along-the-route reads a fixed Debug route and keeps only
/// places in its corridor; call reads the address book only when asked and explains a refusal.
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

        typed(app, "home")
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 45),
                      "home did not open the route chooser: \(debugText("search-debug") ?? "none")")
        report("cmd_kind", "home")
        shot("search-command")
        closeRoute(app)

        typed(app, "work")
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 45),
                      "work did not open the route chooser: \(debugText("search-debug") ?? "none")")
        report("cmd_kind", "work")
        closeRoute(app)

        typed(app, "directions to coffee")
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 90),
                      "directions did not open the route chooser: \(debugText("search-debug") ?? "none")")
        report("cmd_kind", "directions")
        closeRoute(app)

        typed(app, "search along the route coffee")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 90),
                      "along route returned no row: \(debugText("search-debug") ?? "none")")
        let along = debugValues(app)
        XCTAssertTrue((along["cmd_found"] ?? "0") != "0", "the corridor kept nothing")
        report("cmd_kind", "along")
        report("cmd_corridor_m", along["cmd_corridor_m"] ?? "none")
        report("cmd_found", along["cmd_found"] ?? "none")
        shot("search-along-route")

        typed(app, "call Ada Lovelace")
        XCTAssertTrue(waitUntil(20) {
            (self.debugValues(app)["cmd_kind"] ?? "") == "call"
                && (self.debugValues(app)["cmd_contacts"] ?? "") == "denied"
        }, "call did not report the refusal: \(debugText("search-debug") ?? "none")")
        report("cmd_kind", "call")
        report("cmd_contacts", "denied")

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
        report("cmd_kind", "call")
        report("cmd_contacts", "granted")
    }

    private func typed(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["search-field"]
        field.tap()
        let clear = app.buttons["search-clear"]
        if clear.waitForExistence(timeout: 2) {
            clear.tap()
            field.tap()
        }
        field.typeText(text + "\n")
    }

    private func closeRoute(_ app: XCUIApplication) {
        let close = app.buttons["route-close"]
        if close.waitForExistence(timeout: 10) { close.tap() }
        sleep(1)
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
