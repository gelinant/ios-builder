import XCTest

/// ROAD-MARKINGS: the painted road surface at street zoom. The Debug fixture answers Overpass
/// from the requested box, so the same three streets exist in every launch: a four-lane street,
/// a one-way bike lane, a plain one-way street and a bus lane. The screenshots are the visual
/// proof; the report lines name the source the sheet says is drawing.
final class RoadMarkingsUITests: VelaUITestCase {
    private let fixture = ["-VelaResetSettings", "YES", "-VelaMapLayersFixture", "YES"]

    func testPaintedMarksAtStreetZoom() {
        var app = launch(camera: "37.7749,-122.4194,17", arguments: fixture)
        let line = enablePainted(app)
        XCTAssertTrue(line.contains("marks_source=tiles"),
                      "the optional pack is not installed in this build: \(line)")
        let count = field(line, "marks_count")
        XCTAssertGreaterThan(count, 0, "no painted mark reached the map: \(line)")
        let zoom = doubleField(line, "marks_zoom")
        XCTAssertGreaterThanOrEqual(zoom, 16.5, "the marks drew below Android's zoom gate")
        report("marks_source", value(line, "marks_source"))
        report("marks_count", count)
        report("marks_zoom", value(line, "marks_zoom"))
        report("paint_layers", field(line, "paint_layers"))
        report("paint_features", field(line, "paint_features"))
        report("paint_marks", field(line, "paint_marks"))
        report("paint_built", field(line, "paint_built"))
        report("paint_src", field(line, "paint_src"))
        XCTAssertGreaterThan(field(line, "paint_layers"), 0, "no painted layer reached the style: \(line)")
        XCTAssertGreaterThan(field(line, "paint_built"), 0, "no painted feature was built: \(line)")
        XCTAssertGreaterThan(field(line, "paint_vis"), 0, "every painted layer is hidden: \(line)")
        shot("road-markings")

        app.terminate()
        app = launch(camera: "37.77435,-122.4194,17.0", arguments: fixture)
        _ = enablePainted(app)
        shot("road-bike-lane")

        app.terminate()
        app = launch(camera: "37.77545,-122.4194,17.0", arguments: fixture)
        _ = enablePainted(app)
        shot("road-oneway")
        app.terminate()
    }

    /// Opens the sheet, proves the pack offer names its size, switches the layer on and waits for
    /// the first marks. Returns the debug line.
    private func enablePainted(_ app: XCUIApplication) -> String {
        openMapAction("layers-button", in: app)
        XCTAssertTrue(app.buttons["layer-painted"].waitForExistence(timeout: 10), "no layers sheet")

        let row = app.buttons["layer-painted"]
        if row.value as? String != "on" { row.tap() }
        XCTAssertTrue(waitUntil(5) { app.buttons["layer-painted"].value as? String == "on" })

        let download = app.buttons["painted-pack-download"]
        for _ in 0..<5 where !download.exists { app.swipeUp() }
        XCTAssertTrue(download.exists, "the sheet must offer the absent painted pack")
        XCTAssertTrue(download.label.contains("\(PaintedPackSize.mb) MB"),
                      "the offer must name the download size: \(download.label)")
        app.buttons["layers-close"].tap()

        XCTAssertTrue(waitUntil(60) {
            let line = debugText("layers-debug") ?? ""
            return line.contains("painted=ready:") && field(line, "marks_count") > 0
                && field(line, "paint_layers") > 0 && field(line, "paint_built") > 0
        }, "painted marks never reached the style: \(debugText("layers-debug") ?? "no debug line")")
        sleep(2)
        return debugText("layers-debug") ?? ""
    }

    private func value(_ line: String, _ key: String) -> String {
        guard let part = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return ""
        }
        return String(part.dropFirst(key.count + 1))
    }

    private func field(_ line: String, _ key: String) -> Int {
        Int(value(line, key)) ?? 0
    }

    private func doubleField(_ line: String, _ key: String) -> Double {
        Double(value(line, key)) ?? 0
    }
}

/// Kept outside the test case so the expected size is one literal (the UI test target does not
/// import the app module). It mirrors `PaintedPack.sizeMB`.
private enum PaintedPackSize {
    static let mb = 66
}
