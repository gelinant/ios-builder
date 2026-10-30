import XCTest

/// The live calibration: in a Debug build the map shows `calibration <version>`, which reaches
/// the signed bundle's version (27 or later) once the startup refresh has fetched and verified it,
/// or right away from the cache of an earlier launch. Needs the network on a first launch.
final class CalibrationUITests: VelaUITestCase {
    func testLiveCalibrationIsLoaded() {
        launch(camera: "sf")
        var version = 0
        let loaded = waitUntil(60) {
            version = Int(debugText("calibration-debug")?.split(separator: " ").last ?? "") ?? 0
            return version >= 27
        }
        report("calibration_version", version)
        shot("calibration")
        XCTAssertTrue(loaded, "calibration version \(version), want 27 or later")
    }
}
