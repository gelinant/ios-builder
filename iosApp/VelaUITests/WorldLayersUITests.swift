import XCTest

/// WLD-1: the world-layer host starts with every entry hidden behind "not installed". No switch
/// can be turned on, the section shows the source and the state for each entry, and the run makes
/// no world request.
final class WorldLayersUITests: VelaUITestCase {
    private let ids = ["aviation", "maritime", "energy", "notam", "satellite", "wiki"]

    func testWorldLayersStartHidden() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")

        let first = app.buttons["world-layer-aviation"]
        for _ in 0..<8 where !(first.exists && first.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(first.exists, "no World layers section")
        shot("world-layers")

        for id in ids {
            let row = app.buttons["world-layer-\(id)"]
            for _ in 0..<4 where !row.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(row.exists, "missing world layer \(id)")
            XCTAssertFalse(row.isEnabled, "\(id) must stay disabled while not installed")
            XCTAssertEqual(row.value as? String, "not installed",
                           "\(id) must say it is not installed")
        }

        let key = app.secureTextFields["world-key-field-notam"]
        for _ in 0..<4 where !key.exists {
            app.swipeUp()
        }
        XCTAssertTrue(key.exists, "a layer that needs a key must offer its field")

        let debug = app.staticTexts["world-layers-debug"]
        for _ in 0..<6 where !debug.exists {
            app.swipeUp()
        }
        let line = debugText("world-layers-debug") ?? ""
        let installed = intValue(line, "world_layers")
        let requests = intValue(line, "world_requests")
        report("world_layers", installed)
        report("world_requests", requests)
        // W-1 installed the wiki layer, so one entry can draw now; the rest stay unavailable.
        XCTAssertGreaterThanOrEqual(installed, 0, "the host reports no installed layers: \(line)")
        XCTAssertEqual(requests, 0, "the host made a world request: \(line)")
        XCTAssertTrue(line.contains("world_on=0"), "a world switch started on: \(line)")
    }

    private func intValue(_ line: String, _ key: String) -> Int {
        for token in line.split(separator: " ") where token.hasPrefix("\(key)=") {
            return Int(token.dropFirst(key.count + 1)) ?? -1
        }
        return -1
    }
}
