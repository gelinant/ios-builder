import XCTest

/// The Mapbox spike (docs/ios/MAPBOX-SPIKE.md) next to the current WebMap on the same San
/// Francisco cameras. On each camera, once the view has settled, both run the same scripted motion
/// for the frame rate: bearing +360 degrees over 10 s at pitch 60. Without a Mapbox token the
/// Mapbox render checks are skipped with an explicit XCTSkip; the SDK link, the screen and the
/// WebMap numbers are still checked.
final class MapboxSpikeUITests: VelaUITestCase {
    private static let twinPeaks = "37.7544,-122.4477"
    private static let downtown = "37.7915,-122.3990"
    /// Same names and cameras as `MapboxSpikeCamera`; bearing 200 and pitch 60 for all three.
    private static let cameras: [(name: String, camera: String)] = [
        ("twinpeaks-z15", "\(twinPeaks),15"),
        ("twinpeaks-z17", "\(twinPeaks),17"),
        ("downtown-z16", "\(downtown),16"),
    ]

    func testMapboxSpikeOnTheFixtureCameras() throws {
        let app = launch(camera: "sf", waitForMap: false, arguments: ["-VelaMapboxSpike", "YES"])
        let status = app.staticTexts["mapbox-spike-debug"]
        XCTAssertTrue(status.waitForExistence(timeout: 60), "the Mapbox spike screen did not open")
        let first = status.label
        let sdk = value("sdk", in: first)
        report("mapbox_sdk", sdk.isEmpty ? "missing" : sdk)
        XCTAssertFalse(sdk.isEmpty || sdk == "0", "MapboxCoreMaps is not linked: \(first)")

        let hasToken = value("token", in: first) == "1"
        report("mapbox_token", hasToken ? 1 : 0)
        guard hasToken else {
            XCTAssertTrue(app.staticTexts["mapbox-no-token"].exists, "no missing-token label")
            shot("mapbox-no-token")
            report("mapbox_render", "skipped_no_token")
            throw XCTSkip("Mapbox token missing: MAPBOX_ACCESS_TOKEN was empty at build time, so the Mapbox render was not checked")
        }

        XCTAssertTrue(waitUntil(90) { value("style", in: status.label) == "1" },
                      "the Standard style never loaded: \(status.label)")
        report("mapbox_style_loaded", 1)
        report("mapbox_style_ms", value("style_ms", in: status.label))

        for fixture in Self.cameras {
            let key = fixture.name.replacingOccurrences(of: "-", with: "_")
            let button = app.buttons["spike-camera-\(fixture.name)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(fixture.name) button")
            button.tap()
            let settled = waitUntil(90) {
                let line = status.label
                return value("camera", in: line) == fixture.name && value("idle", in: line) == "1"
            }
            report("mapbox_idle_\(key)", settled ? 1 : 0)
            sleep(2)
            shot("mapbox-\(fixture.name)")
            if fixture.name == "twinpeaks-z15" {
                let terrainLine = status.label
                let terrainOn = value("terrain", in: terrainLine) == "1"
                report("mapbox_terrain", terrainOn ? 1 : 0)
                report("mapbox_elevation_m", value("peak", in: terrainLine))
                report("mapbox_loaded_ms", value("loaded_ms", in: terrainLine))
                XCTAssertTrue(terrainOn, "no terrain under Twin Peaks: \(terrainLine)")
            }

            app.buttons["spike-fps-run"].tap()
            XCTAssertTrue(waitUntil(90) { Double(value("fps", in: status.label)) != nil },
                          "the Mapbox FPS motion never reported on \(fixture.name): \(status.label)")
            let fpsLine = status.label
            report("mapbox_fps_\(key)", value("fps", in: fpsLine))
            report("mapbox_frames_\(key)", value("frames", in: fpsLine))
            report("mapbox_ticks_\(key)", value("ticks", in: fpsLine))
            if fixture.name == "twinpeaks-z15" {
                report("mapbox_fps", value("fps", in: fpsLine))
                report("mapbox_frames", value("frames", in: fpsLine))
            }
        }
        report("mapbox_errors", value("errors", in: status.label))
        shot("mapbox-fps-end")
    }

    func testWebMapOnTheSameCamerasAndFps() {
        for fixture in Self.cameras {
            let key = fixture.name.replacingOccurrences(of: "-", with: "_")
            // The probe waits for every tile of the view, holds 3 s for the screenshot, then turns.
            let app = launch(camera: fixture.camera,
                             arguments: ["-VelaMapPitch", "60", "-VelaMapBearing", "200", "-VelaFpsProbe", "5"])
            let probe = app.staticTexts["map-fps-debug"]
            XCTAssertTrue(probe.waitForExistence(timeout: 10), "no WebMap FPS probe line")
            let ready = waitUntil(150) {
                let state = value("fps", in: probe.label)
                return state == "settled" || state == "timeout" || Double(state) != nil
            }
            let settleLine = probe.label
            report("webmap_settle_\(key)", ready ? value("fps", in: settleLine) : "none")
            report("webmap_settle_ms_\(key)", value("waited_ms", in: settleLine))
            shot("webmap-\(fixture.name)")
            XCTAssertTrue(waitUntil(60) { Double(value("fps", in: probe.label)) != nil },
                          "the WebMap FPS probe never reported on \(fixture.name): \(probe.label)")
            let line = probe.label
            report("webmap_fps_\(key)", value("fps", in: line))
            report("webmap_frames_\(key)", value("frames", in: line))
            report("webmap_ticks_\(key)", value("ticks", in: line))
            if fixture.name == "twinpeaks-z15" {
                report("webmap_fps", value("fps", in: line))
                report("webmap_frames", value("frames", in: line))
                shot("webmap-fps-end")
            }
            app.terminate()
        }
    }

    /// The text after `key=` in a space separated status line, or "" when the key is absent.
    private func value(_ key: String, in line: String) -> String {
        guard let token = line.split(separator: " ").first(where: { $0.hasPrefix("\(key)=") }) else {
            return ""
        }
        return String(token.dropFirst(key.count + 1))
    }
}
