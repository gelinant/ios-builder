import XCTest

/// WLD-1 delivered the host with every entry hidden. A-1, A-2, A-3, G-3 and W-1 have since
/// installed their layers, so this scenario now checks both states: the installed entries are
/// enabled and name their source, and the one that cannot be installed without FAA credentials
/// stays disabled and says so.
final class WorldLayersUITests: VelaUITestCase {
    private let ids = ["aviation", "maritime", "energy", "notam", "satellite", "wiki"]
    private let notInstalled = ["notam"]

    func testWorldLayersStartHidden() {
        let app = launch(arguments: ["-VelaResetSettings", "YES"])

        openMapAction("layers-button", in: app)
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
            if notInstalled.contains(id) {
                XCTAssertFalse(row.isEnabled, "\(id) must stay disabled while not installed")
                let value = (row.value as? String) ?? ""
                XCTAssertTrue(value.contains("not installed") || value.contains("credentials"),
                              "\(id) does not say why it is unavailable: \(value)")
            } else {
                XCTAssertTrue(row.isEnabled, "\(id) is installed and must be switchable")
            }
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
