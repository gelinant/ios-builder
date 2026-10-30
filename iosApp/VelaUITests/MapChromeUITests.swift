import XCTest

/// MAP-CHROME: the map chrome must fit the safe area whatever sheet owns the bottom. The bug hunt
/// measured `saved-open` with no hit point and `steps-close` at y=880 when a sheet was open: the
/// old single VStack overflowed and was centred. This scenario opens the route steps sheet, the
/// tallest bottom sheet, and requires the search row, its overflow and Saved to stay hittable.
final class MapChromeUITests: VelaUITestCase {
    func testChromeFitsWithSheetOpen() {
        let app = launch(camera: "sf", followUser: true,
                         arguments: ["-VelaResetSettings", "YES"])
        let searchField = app.textFields["search-field"]
        sleep(4)
        searchField.tap()
        searchField.typeText("coffee\n")

        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no coffee result")
        sleep(3)
        rows.firstMatch.tap()
        let directions = app.buttons["place-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 15), "no Directions button")
        directions.tap()
        XCTAssertTrue(app.otherElements["route-sheet"].waitForExistence(timeout: 10)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 5),
                      "no route chooser")
        XCTAssertTrue(waitUntil(120) {
            let line = self.debugText("route-debug") ?? ""
            return line.contains("loading=0") && !line.contains("routes=0")
        }, "no driving route: \(debugText("route-debug") ?? "none")")

        let steps = app.buttons["route-steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 10), "no steps action")
        if !steps.isHittable {
            app.otherElements["route-sheet"].swipeUp()
        }
        steps.tap()
        let close = app.buttons["steps-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10), "no steps sheet")

        let field = app.textFields["search-field"]
        let overflow = app.buttons["map-overflow"]
        let saved = app.buttons["saved-open"]
        let overflowed = !field.isHittable || !overflow.isHittable
            || !saved.isHittable || !close.isHittable
        if overflowed {
            // Give SwiftUI one layout pass before declaring the chrome off screen.
            _ = waitUntil(5) {
                field.isHittable && overflow.isHittable && saved.isHittable && close.isHittable
            }
        }
        XCTAssertTrue(field.isHittable,
                      "search-field is not hittable with the steps sheet open: \(chromeFrames(app))")
        XCTAssertTrue(overflow.isHittable,
                      "map-overflow is not hittable with the steps sheet open: \(chromeFrames(app))")
        XCTAssertTrue(saved.isHittable,
                      "saved-open is not hittable with the steps sheet open: \(chromeFrames(app))")
        XCTAssertTrue(close.isHittable,
                      "steps-close is not hittable with the steps sheet open: \(chromeFrames(app))")
        shot("chrome-fit")
        report("chrome_overflow", 0)
        report("chrome_search_y", String(format: "%.1f", field.frame.minY))
        report("chrome_steps_close_y", String(format: "%.1f", close.frame.minY))
    }

    /// The frames that made the old failure readable (`{inf, inf}` or a y under the window).
    private func chromeFrames(_ app: XCUIApplication) -> String {
        let ids = ["search-field", "map-overflow", "saved-open", "steps-close"]
        return ids.map { id in
            let element = app.descendants(matching: .any)[id]
            return "\(id)=\(element.exists ? String(describing: element.frame) : "missing")"
        }.joined(separator: " ")
    }
}
