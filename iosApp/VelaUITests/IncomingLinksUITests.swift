import XCTest

/// Incoming Google Maps links. The launch URL stands in for `onOpenURL`, so these scenarios cover
/// the cold start path; the router and warm path are the same one (IntentsTests/IncomingLinksTests).
/// Fixtures are in Davis and Sacramento, with no personal location.
final class IncomingLinksUITests: VelaUITestCase {
    private let davisFoodCoop = "https://www.google.com/maps/place/Davis+Food+Co-op/" +
        "@38.5449065,-121.7405167,17z/data=!3m1!4b1!4m6!3m5!1s" +
        "0x808529999495543f:0xed7bb8fb4c8510c0!8m2!3d38.5449065!4d-121.7405167"

    private let sacramentoToDavis = "https://www.google.com/maps/dir/?api=1" +
        "&origin=38.5815719,-121.4943996&destination=38.5449065,-121.7405167&travelmode=driving"

    func testIncomingPlaceLinkOpensThePlaceSheet() {
        let app = launch(camera: "davis", arguments: ["-VelaOpenURL", davisFoodCoop])
        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 90), "incoming place link did not open a place")
        XCTAssertTrue(name.label.localizedCaseInsensitiveContains("Davis"),
                      "unexpected place for the link: \(name.label)")
        shot("incoming-place")
        report("incoming_place", name.label.replacingOccurrences(of: " ", with: "_"))
    }

    func testIncomingDirectionsLinkOpensTheChooser() {
        let app = launch(camera: "davis", arguments: ["-VelaOpenURL", sacramentoToDavis])
        let chooser = app.otherElements["route-sheet"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 90)
            || app.buttons["route-mode-DRIVE"].waitForExistence(timeout: 10),
            "incoming directions link did not open the route chooser")
        let destination = app.staticTexts["route-destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 15), "the chooser has no destination")
        shot("incoming-directions")
        report("incoming_directions", destination.label.replacingOccurrences(of: " ", with: "_"))
    }

    func testBareCidLinkShowsTheVelaError() {
        let app = launch(arguments: [
            "-VelaOpenURL", "https://maps.google.com/?cid=1234567890123456789",
        ])
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10),
                      "a cid-only link did not show the Vela error")
        XCTAssertTrue(app.buttons["Open Saved"].firstMatch.exists)
        report("incoming_cid_error", "shown")
    }
}
