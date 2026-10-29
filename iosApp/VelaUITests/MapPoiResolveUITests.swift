import XCTest

/// POI-RESOLVE: a tap on a basemap label always opens something. A confident Google match keeps
/// the full place sheet; a miss, or a reply that names another business, opens the OpenStreetMap
/// sheet built from the tapped vector label, with the actions that need no Google.
///
/// Both scenarios drive a fixed answer set through the real decision (`-VelaMapPoiFixture`), so
/// they need no network and cannot drift with the live map data.
final class MapPoiResolveUITests: VelaUITestCase {
    func testTapFallsBackToOsmPlace() {
        let app = launch(camera: "sf", arguments: ["-VelaMapPoiFixture", "fallback"])

        let sheet = app.descendants(matching: .any)["map-poi-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "a tap with no Google match opened nothing")
        XCTAssertFalse(app.descendants(matching: .any)["place-sheet"].exists,
                       "a far reply must not open a Google place sheet")

        XCTAssertEqual(app.staticTexts["map-poi-name"].label, "Vela Test Cafe")
        XCTAssertTrue(app.descendants(matching: .any)["map-poi-osm"].exists,
                      "the sheet does not say it is an OpenStreetMap place")
        XCTAssertTrue(app.staticTexts["map-poi-coordinates"].exists, "no coordinates")
        XCTAssertTrue(app.descendants(matching: .any)["map-poi-distance"].exists, "no distance from the user")
        XCTAssertTrue(app.buttons["map-poi-directions"].exists, "no directions action")
        XCTAssertTrue(app.buttons["map-poi-share"].exists, "no share action")
        XCTAssertTrue(app.buttons["map-poi-search-google"].exists, "no explicit Google lookup")

        let share = app.buttons["map-poi-share"].value as? String ?? ""
        XCTAssertTrue(share.contains("https://www.openstreetmap.org/"), "the share link is not OSM: \(share)")
        XCTAssertFalse(share.contains("google.com/maps"), "the OSM sheet shared a Google link: \(share)")

        let debug = debugText("map-poi-debug") ?? ""
        XCTAssertTrue(debug.contains("poi_match=fallback"), "debug line: \(debug)")
        report("poi_match", "fallback")
        shot("poi-osm-sheet")

        // The save action writes the label itself, not a nearby Google listing.
        app.buttons["map-poi-save"].tap()
        XCTAssertTrue(waitUntil(10) { app.buttons["map-poi-save"].label.contains("Saved") },
                      "the map label was not saved")
    }

    func testTapKeepsExactGooglePlace() {
        let app = launch(camera: "sf", arguments: ["-VelaMapPoiFixture", "exact"])

        let sheet = app.descendants(matching: .any)["place-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "an agreeing Google match opened nothing")
        XCTAssertFalse(app.descendants(matching: .any)["map-poi-sheet"].exists,
                       "an exact match must not show the OSM fallback under the place sheet")
        XCTAssertEqual(app.staticTexts["place-name"].label, "Ferry Building")

        XCTAssertTrue(waitUntil(10) { (debugText("place-debug") ?? "").contains("poi_match=exact") },
                      "debug line: \(debugText("place-debug") ?? "none")")
        report("poi_match", "exact")
        shot("poi-google-sheet")
    }
}
