import XCTest

/// MAP-TAP: every drawn kind opens its own sheet. Four launches, one per kind, each over a
/// deterministic camera or fixture, so the screenshots and the `tap_kind` lines stay readable.
final class MapTapUITests: VelaUITestCase {
    private let savedFixture = """
    [{"id":"list:maptap:pins","name":"Map Tap Saved List","icon":"bookmark","color":4280391411,\
    "places":[{"id":"maptap:centre","name":"Map Tap Saved","lat":37.7749,"lng":-122.4194,\
    "address":"Market St"}]}]
    """

    func testTapEachKindOpensItsSheet() {
        tapPlace()
        tapCamera()
        tapAircraft()
        tapSaved()
    }

    /// A named Vela pack place in Davis opens a place sheet. A transit stop can be
    /// the topmost symbol at the exact centre, so the test walks a small ring and closes a transit
    /// board before trying the next point; a place must open at one of them.
    private func tapPlace() {
        let app = launch(camera: "38.543836,-121.746331,17")
        sleep(8)
        XCTAssertTrue(openPlaceSheet(), "a place tap opened no sheet: \(tapDebugLine())")
        shot("tap-place")
        report("tap_kind", "place")
        report("tap_debug", tapDebugLine())
        if app.staticTexts["place-name"].exists {
            app.buttons["place-close"].tap()
        } else {
            app.buttons["map-poi-close"].tap()
        }
    }

    private func openPlaceSheet() -> Bool {
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 20), "no map")
        let offsets: [(CGFloat, CGFloat)] = [
            (0.50, 0.50), (0.49, 0.50), (0.51, 0.50),
            (0.50, 0.49), (0.50, 0.51),
        ]
        for (dx, dy) in offsets {
            map.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
            if waitUntil(4, {
                app.staticTexts["place-name"].exists || app.staticTexts["map-poi-name"].exists
            }) {
                return true
            }
            print("UITEST tap_probe=\(tapDebugLine())")
            if app.buttons["transit-board-close"].exists {
                app.buttons["transit-board-close"].tap()
            } else if app.buttons["map-tap-card-close"].exists {
                app.buttons["map-tap-card-close"].tap()
            }
            usleep(400_000)
        }
        return false
    }

    /// The layer fixture puts a speed camera at the box centre, so the map centre is a camera.
    private func tapCamera() {
        let app = launch(
            camera: "37.7749,-122.4194,17",
            arguments: ["-VelaResetSettings", "YES", "-VelaMapLayersFixture", "YES"])
        let layers = app.buttons["layers-button"]
        XCTAssertTrue(layers.waitForExistence(timeout: 30), "no layers button")
        layers.tap()
        let speed = app.buttons["layer-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 10), "no speed switch")
        if speed.value as? String != "on" { speed.tap() }
        XCTAssertTrue(waitUntil(5) { app.buttons["layer-speed"].value as? String == "on" },
                      "the speed switch did not turn on")
        app.buttons["layers-close"].tap()
        XCTAssertTrue(waitUntil(45) {
            debugText("layers-debug")?.contains("speed=ready:") == true
        }, "the speed camera never reached ready: \(debugText("layers-debug") ?? "no line")")
        sleep(2)

        tapCenter()
        let card = app.descendants(matching: .any)["map-tap-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "a camera tap opened no card")
        let kind = app.staticTexts["map-tap-card-kind"]
        XCTAssertTrue(kind.exists && kind.label.lowercased().contains("camera"),
                      "the card is not a camera card: \(kind.label)")
        shot("tap-camera")
        report("tap_kind", "camera")
        report("tap_debug", tapDebugLine())
        app.buttons["map-tap-card-close"].tap()
    }

    /// The captured adsb.lol answer has an aircraft at the camera centre. The World layer only
    /// refreshes after a camera move, so the test turns it on, pans once, then relaunches on the
    /// plane and pans away and back to force the second refresh without leaving the fixture.
    private func tapAircraft() {
        let first = launch(
            camera: "37.626217,-122.395351,13",
            arguments: ["-VelaResetSettings", "YES", "-VelaAviationFixture", "YES"])
        enableAviation(first)
        pan(first, dx: 0.62, to: 0.38)
        sleep(12)

        let app = launch(
            camera: "37.626217,-122.395351,13",
            arguments: ["-VelaAviationFixture", "YES"])
        enableAviation(app)
        pan(app, dx: 0.58, to: 0.42)
        sleep(4)
        pan(app, dx: 0.42, to: 0.58)
        sleep(12)

        let card = app.descendants(matching: .any)["aviation-detail-card"]
        let offsets: [(CGFloat, CGFloat)] = [
            (0.50, 0.50), (0.49, 0.50), (0.51, 0.50), (0.50, 0.49), (0.50, 0.51),
        ]
        for (dx, dy) in offsets {
            let map = app.descendants(matching: .any)["map"]
            map.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
            if card.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(card.exists, "an aircraft tap opened no card: \(tapDebugLine())")
        XCTAssertTrue(app.staticTexts["aviation-detail-ident"].exists,
                      "the aircraft card has no identification")
        shot("tap-aircraft")
        report("tap_kind", "aircraft")
        report("tap_debug", tapDebugLine())
        app.buttons["aviation-detail-close"].tap()
    }

    private func enableAviation(_ app: XCUIApplication) {
        let layers = app.buttons["layers-button"]
        XCTAssertTrue(layers.waitForExistence(timeout: 30), "no layers button")
        layers.tap()
        let aviation = app.buttons["world-layer-aviation"]
        for _ in 0..<12 where !(aviation.exists && aviation.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(aviation.exists, "no aviation row")
        if aviation.value as? String != "on" { aviation.tap() }
        XCTAssertTrue(waitUntil(5) {
            app.buttons["world-layer-aviation"].value as? String == "on"
        }, "the aviation switch did not turn on")
        app.buttons["layers-close"].tap()
    }

    /// A saved place at the camera centre outranks the basemap and opens the saved place sheet.
    private func tapSaved() {
        let app = launch(
            camera: "37.7749,-122.4194,15",
            arguments: ["-VelaSavedFixtureText", savedFixture])
        app.buttons["saved-open"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 10),
                      "Saved did not open")
        let list = app.buttons.matching(identifier: "saved-list")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Map Tap Saved List"))
            .firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "the saved fixture never imported")
        app.buttons["saved-close"].tap()
        sleep(3)

        tapCenter()
        let name = app.staticTexts["place-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 20),
                      "a saved pin opened no place: \(tapDebugLine())")
        XCTAssertEqual(name.label, "Map Tap Saved", "the wrong saved place opened")
        shot("tap-saved")
        report("tap_kind", "saved")
        report("tap_debug", tapDebugLine())
        app.buttons["place-close"].tap()
    }

    private func tapDebugLine() -> String {
        debugText("layers-debug") ?? "no-layers-debug"
    }

    private func tapCenter() {
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 20), "no map")
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func pan(_ app: XCUIApplication, dx: CGFloat, to endX: CGFloat) {
        let map = app.descendants(matching: .any)["map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10), "no map")
        let start = map.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.58))
        let end = map.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.58))
        start.press(forDuration: 0.2, thenDragTo: end)
    }
}
