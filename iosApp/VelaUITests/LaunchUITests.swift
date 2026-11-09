import XCTest

/// The map screen comes up over each fixture camera with its controls.
final class LaunchUITests: VelaUITestCase {
    func testLaunchShowsTheMapOverSanFrancisco() {
        let app = launch(camera: "sf")
        XCTAssertTrue(app.buttons["Show my location"].exists, "no location button")
        report("map_element", app.descendants(matching: .any)["map"].exists ? "yes" : "no")
        // Lets the tiles land.
        sleep(8)
        shot("launch-sf")
    }

    func testStartCameraArgumentMovesTheMapToDavis() {
        launch(camera: "davis")
        sleep(8)
        shot("launch-davis")
    }
}
