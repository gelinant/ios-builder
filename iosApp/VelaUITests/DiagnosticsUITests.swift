import XCTest

/// TRIP-DIAG end to end: the performance overlay draws on the map, its reading reaches
/// Diagnostics, and a crash report is copied and exported through the redacted file.
/// Screenshots: diagnostics-perf.png, diagnostics-crash.png. Report lines: diag_fps,
/// diag_crash_exported.
final class DiagnosticsUITests: VelaUITestCase {
    func testCrashExportAndPerfOverlay() throws {
        let app = launch(camera: "sf", followUser: true)

        // Turn the overlay on from Diagnostics (Debug builds already default to on).
        app.buttons["trips-open"].tap()
        let diagnosticsButton = app.buttons["trips-diagnostics"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 10), "no Diagnostics entry")
        diagnosticsButton.tap()

        let perf = app.staticTexts["diagnostics-perf"]
        XCTAssertTrue(perf.waitForExistence(timeout: 10), "no performance line")
        let toggle = app.switches["diagnostics-perf-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no overlay switch")
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitUntil(5) { (toggle.value as? String) == "1" },
                      "the overlay switch did not turn on")
        app.buttons["diagnostics-done"].tap()
        app.buttons["trips-done"].tap()

        // Let the display link fill a window, then capture the map with the overlay.
        sleep(3)
        shot("diagnostics-perf")

        // Read the live reading from Diagnostics.
        app.buttons["trips-open"].tap()
        XCTAssertTrue(app.buttons["trips-diagnostics"].waitForExistence(timeout: 10))
        app.buttons["trips-diagnostics"].tap()
        XCTAssertTrue(perf.waitForExistence(timeout: 10), "no performance line on the second visit")
        XCTAssertTrue(waitUntil(6) { (self.fps(in: perf) ?? 0) > 0 },
                      "no frame rate: \(perf.label)")
        let rate = fps(in: perf) ?? 0
        report("diag_fps", rate)
        XCTAssertTrue(perf.label.contains("dropped="), "no dropped-frame count: \(perf.label)")
        XCTAssertTrue(perf.label.contains("tiles="), "no tile count: \(perf.label)")
        XCTAssertTrue(perf.label.contains("mem="), "no memory figure: \(perf.label)")
        XCTAssertTrue(perf.label.contains("zoom="), "no zoom figure: \(perf.label)")

        // The four measurements are recorded with a timestamp; only launch and first frame are
        // guaranteed by the time this screen opens.
        let measurements = app.staticTexts["diagnostics-measurements"]
        XCTAssertTrue(measurements.waitForExistence(timeout: 10), "no measurements")
        XCTAssertTrue(measurements.label.contains("launch:"), measurements.label)
        XCTAssertTrue(measurements.label.contains(" s at "), measurements.label)
        XCTAssertTrue(measurements.label.contains("first map frame:"), measurements.label)

        // A sample crash report gives copy and export something to hand over.
        let sample = app.buttons["diagnostics-crash-sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10), "no sample crash action")
        reveal(sample, in: app)
        sample.tap()
        XCTAssertTrue(waitUntil(5) {
            app.staticTexts.matching(identifier: "diagnostics-crash-row").count > 0
        }, "the sample crash report is not listed")
        XCTAssertTrue(app.buttons["diagnostics-crash-copy"].isEnabled)
        reveal(app.buttons["diagnostics-crash-copy"], in: app)
        app.buttons["diagnostics-crash-copy"].tap()
        XCTAssertTrue(app.staticTexts["diagnostics-crash-status"].waitForExistence(timeout: 5),
                      "copy gave no confirmation")
        shot("diagnostics-crash")

        // Export must present the share sheet with the redacted file.
        reveal(app.buttons["diagnostics-crash-export"], in: app)
        app.buttons["diagnostics-crash-export"].tap()
        let presented = waitUntil(10) {
            app.otherElements["ActivityListView"].exists
                || app.buttons["Close"].exists
                || app.buttons["Copy"].exists
        }
        XCTAssertTrue(presented, "the crash export did not present a share sheet")
        report("diag_crash_exported", 1)
    }

    /// Scrolls a diagnostics section into reach before a tap.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.scrollViews.firstMatch.swipeUp()
            tries += 1
        }
    }

    /// The `fps=` number of a performance line, or nil while it still reads zero/absent.
    private func fps(in element: XCUIElement) -> Int? {
        guard element.exists else { return nil }
        for part in element.label.split(separator: " ") where part.hasPrefix("fps=") {
            return Int(part.dropFirst("fps=".count))
        }
        return nil
    }
}
