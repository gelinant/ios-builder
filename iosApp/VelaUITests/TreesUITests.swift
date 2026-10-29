import XCTest

/// TREES-LAYER: the trees switch, the OSM tree discs at close zoom, the z17 gate and the canopy
/// polygons from the vector tiles. The tree answer is the deterministic Debug fixture, so no
/// Overpass mirror decides whether the scenario passes.
final class TreesUITests: VelaUITestCase {
    func testTreesAndCanopyAtHighZoom() {
        // Golden Gate Park: the vector tiles carry real forest and park polygons here.
        let app = launch(
            camera: "37.7694,-122.4862,17.6",
            arguments: ["-VelaResetSettings", "YES",
                        "-VelaMapLayersFixture", "YES",
                        "-VelaTreesFixture", "YES"])

        let button = app.buttons["layers-button"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "no layers button")
        button.tap()

        let trees = app.buttons["layer-trees"]
        XCTAssertTrue(revealInSheet(trees, in: app), "no trees switch")
        XCTAssertEqual(trees.value as? String, "off", "trees must start off")
        trees.tap()
        XCTAssertTrue(waitUntil(5) { app.buttons["layer-trees"].value as? String == "on" },
                      "the trees switch did not turn on")
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(30) {
            guard let line = debugText("layers-debug") else { return false }
            return line.contains("trees=ready:") && line.contains("tree_source=fixture")
        }, "the tree layer never reached ready: \(debugText("layers-debug") ?? "no debug line")")

        let line = debugText("layers-debug") ?? ""
        let count = count(line, "trees")
        report("trees_count", count)
        report("trees_source", "fixture")
        report("trees_zoom_gate", 1)
        XCTAssertGreaterThan(count, 0, "no tree drawn at zoom 17.6")
        sleep(4)
        shot("trees")

        // Below the gate the individual discs disappear and only the canopy polygons remain.
        app.terminate()
        let forest = launch(
            camera: "37.7694,-122.4862,15.2",
            arguments: ["-VelaMapLayersFixture", "YES", "-VelaTreesFixture", "YES"])
        forest.buttons["layers-button"].tap()
        XCTAssertTrue(revealInSheet(forest.buttons["layer-trees"], in: forest),
                      "the trees switch did not persist")
        XCTAssertEqual(forest.buttons["layer-trees"].value as? String, "on",
                       "the trees switch must persist across launches")
        forest.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(20) {
            guard let text = debugText("layers-debug") else { return false }
            return text.contains("trees=zoom:")
        }, "zoom 15.2 did not close the individual-tree gate: \(debugText("layers-debug") ?? "no line")")
        report("trees_zoom_gate", 1)
        XCTAssertFalse(line.contains("trees=zoom:"), "zoom 17.6 was gated out")
        sleep(3)
        shot("trees-forest")

        // Leave the shared settings suite as the other scenarios expect it.
        forest.buttons["layers-button"].tap()
        if revealInSheet(forest.buttons["layer-trees"], in: forest) {
            forest.buttons["layer-trees"].tap()
        }
        forest.buttons["layers-close"].tap()
    }

    private func count(_ line: String, _ key: String) -> Int {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return 0
        }
        let value = part.split(separator: ":").last.map(String.init) ?? ""
        return Int(value) ?? 0
    }
}
