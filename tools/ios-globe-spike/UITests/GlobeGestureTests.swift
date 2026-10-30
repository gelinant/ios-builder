// Gesture probe on the globe: pinch out to the planet, pinch back in, then drag horizontally.
// The camera readout is part of the UI, so the test measures what the user sees. The CI script
// greps the GESTURE lines out of the xcodebuild log.
import XCTest

final class GlobeGestureTests: XCTestCase {
    private func value(_ label: String, _ key: String) -> Double {
        for part in label.split(separator: " ") {
            let fields = part.split(separator: "=")
            if fields.count == 2, fields[0] == Substring(key) {
                return Double(fields[1]) ?? .nan
            }
        }
        return .nan
    }

    private func readout(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["camera-readout"]
    }

    func testGlobePinchAndDrag() {
        let app = XCUIApplication()
        app.launchArguments = ["--gesture"]
        app.launch()

        let label = readout(app)
        XCTAssertTrue(label.waitForExistence(timeout: 90), "camera readout never appeared")
        let ready = NSPredicate(format: "label BEGINSWITH 'zoom='")
        let expectation = XCTNSPredicateExpectation(predicate: ready, object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 90), .completed)

        sleep(2)
        let start = label.label
        print("GESTURE start=\(start)")

        // Pinch out: the planet must come into view, at the minimum zoom.
        app.pinch(withScale: 0.25, velocity: -4)
        sleep(3)
        let afterOut = label.label
        print("GESTURE step=pinch-out before=\(start) after=\(afterOut)")

        // Pinch back in: the globe must zoom back towards the city.
        app.pinch(withScale: 2.5, velocity: 4)
        sleep(3)
        let afterIn = label.label
        print("GESTURE step=pinch-in after=\(afterIn)")

        // Drag: on the globe the place under the finger stays under it, so longitude and bearing
        // both move. Record both rather than asserting a single convention.
        app.swipeLeft()
        sleep(3)
        let afterDrag = label.label
        print("GESTURE step=drag after=\(afterDrag)")

        XCTAssertLessThan(value(afterOut, "zoom"), value(start, "zoom"), "pinching out did not zoom out")
        XCTAssertGreaterThan(value(afterIn, "zoom"), value(afterOut, "zoom"), "pinching in did not zoom in")
        XCTAssertNotEqual(value(afterDrag, "lon"), value(afterIn, "lon"), "drag did not move the map")
    }
}
