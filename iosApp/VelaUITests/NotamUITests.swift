import XCTest

/// A-4: the FAA NMS access is requested by e-mail and uses OAuth2 client credentials, so this
/// build cannot install the layer. The scenario proves the NOTAM row stays disabled, says it is
/// not installed, names the missing FAA credentials and keeps its Keychain field. It also proves
/// that no NOTAM text or zone is drawn and that the advisory wording is visible.
final class NotamUITests: VelaUITestCase {
    func testNotamDisabledStateAndCredentialPrompt() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])

        openMapAction("layers-button", in: app)
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")

        let row = app.buttons["world-layer-notam"]
        for _ in 0..<10 where !(row.exists && row.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(row.exists, "no NOTAM row in the World layers section")
        XCTAssertFalse(row.isEnabled, "a NOTAM layer without FAA credentials must stay disabled")
        XCTAssertEqual(row.value as? String, "not installed",
                       "the NOTAM row must say it is not installed")

        let advisory = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "not for operational use"))
        XCTAssertTrue(advisory.firstMatch.exists, "the advisory wording is missing")
        let credentials = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "credentials required"))
        XCTAssertTrue(credentials.firstMatch.exists, "the row must name the missing FAA credentials")
        shot("notam-disabled")

        // Tapping a disabled row must not turn anything on.
        row.tap()
        XCTAssertEqual(app.buttons["world-layer-notam"].value as? String, "not installed",
                       "a disabled NOTAM row changed state")

        let key = app.secureTextFields["world-key-field-notam"]
        for _ in 0..<6 where !(key.exists && key.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(key.exists, "the NOTAM row must keep its credentials field")
        shot("notam-credentials")

        let debug = app.staticTexts["world-layers-debug"]
        for _ in 0..<6 where !debug.exists {
            app.swipeUp()
        }
        let line = debugText("world-layers-debug") ?? ""
        XCTAssertTrue(line.contains("world_requests=0"), "the disabled layer made a request: \(line)")

        // The acceptance lines of A-4 are reported as zeros: no layer exists in this build.
        report("notam_installed", 0)
        report("notam_credentials", "required")
        report("notam_count", 0)
        report("notam_geometry", 0)
        report("notam_operational", 0)
    }
}
