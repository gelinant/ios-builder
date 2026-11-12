import CoreGraphics
import XCTest

/// A real Liberty feature tap, centered on a known San Francisco POI after its tiles have loaded.
final class MapSearchUITests: VelaUITestCase {
    func testMapPoiTapOpensGooglePlace() {
        let app = launch(camera: "37.7955,-122.3937,18")
        sleep(8)

        // Warm the Google session and center the exact result, then remove its annotation and sheet.
        let field = app.textFields["search-field"]
        field.tap()
        field.typeText("Ferry Building\n")
        let rows = app.buttons.matching(identifier: "search-result")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "no fixture search result")
        rows.firstMatch.tap()
        let resultName = app.staticTexts["place-name"]
        XCTAssertTrue(resultName.waitForExistence(timeout: 15), "no fixture place")
        app.buttons["place-close"].tap()
        app.buttons["search-clear"].tap()
        XCTAssertTrue(waitUntil(10) { !app.staticTexts["place-name"].exists })
        sleep(5)

        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.exists)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 45), "map POI did not open a Google place")
        report("map_poi_name", name.label.replacingOccurrences(of: " ", with: "_"))
        sleep(3)
        shot("map-poi")
    }
}
