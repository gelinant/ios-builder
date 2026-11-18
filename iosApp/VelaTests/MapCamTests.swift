import XCTest
@testable import Vela

/// MAP-CAM: the plate-camera direction wedge. The pack carries a bearing, never a guessed one;
/// the wedge turns with the map, shares the dot's zoom gate, and shortens on the ground at high
/// zoom so it cannot claim more precision than the five-decimal coordinates support.
final class MapCamTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CameraPacks.resetCacheForTest()
    }

    func testScreenBearingTurnsWithTheMap() {
        XCTAssertEqual(CameraCones.screenBearing(directionDeg: 90, mapBearingDeg: 0), 90)
        XCTAssertEqual(CameraCones.screenBearing(directionDeg: 90, mapBearingDeg: 30), 60)
        XCTAssertEqual(CameraCones.screenBearing(directionDeg: 10, mapBearingDeg: 30), 340)
        XCTAssertEqual(CameraCones.screenBearing(directionDeg: 350, mapBearingDeg: 10), 340)
        XCTAssertEqual(CameraCones.screenBearing(directionDeg: 0, mapBearingDeg: 360), 0)
    }

    func testWedgePointsAlongTheBearing() {
        let east = CameraCones.wedge(
            lat: 37.5, lng: -121.5, bearingDeg: 90, lengthM: CameraCones.lengthM)
        XCTAssertEqual(east.count, 10, "apex plus the eight-step arc")
        XCTAssertEqual(east[0], LayerCoordinate(lat: 37.5, lng: -121.5),
                       "the apex sits on the stored camera coordinate")
        XCTAssertGreaterThan(east[5].lng, -121.5, "a 90 degree camera faces east")
        XCTAssertEqual(east[5].lat, 37.5, accuracy: 1e-7)

        let north = CameraCones.wedge(
            lat: 37.5, lng: -121.5, bearingDeg: 0, lengthM: CameraCones.lengthM)
        XCTAssertGreaterThan(north[5].lat, 37.5, "a 0 degree camera faces north")
        XCTAssertEqual(north[5].lng, -121.5, accuracy: 1e-7)

        XCTAssertTrue(CameraCones.wedge(
            lat: 37.5, lng: -121.5, bearingDeg: .nan, lengthM: 30).isEmpty,
            "a malformed bearing draws no wedge instead of a north-facing one")
    }

    func testMissingBearingStaysWithoutACone() throws {
        let data = Data("""
        {"id":"tmp","name":"tmp-2026-01-02","kind":"alpr","generatedAtMs":1767312000000,
         "date":"2026-01-02","s":37.0,"w":-122.0,"n":38.0,"e":-121.0,
         "cameras":[[37.5,-121.5],[37.6,-121.4,90],[37.7,-121.3,360],
                    [37.8,-121.2,450],[37.9,-121.1,-90],
                    {"lat":37.4,"lng":-121.6,"kind":"alpr","direction":180}]}
        """.utf8)
        let pack = try CameraPack(data: data, fallbackKind: "alpr")
        XCTAssertEqual(pack.cameras.map(\.bearing), [nil, 90.0, 0.0, 90.0, 270.0, 180.0])
        XCTAssertEqual(pack.cameras.map(\.lat), [37.5, 37.6, 37.7, 37.8, 37.9, 37.4])
        XCTAssertNil(CameraCones.normalizeBearing(nil))
        XCTAssertNil(CameraCones.normalizeBearing(.infinity))
    }

    func testTheBundledPackCarriesBearingsForMostCameras() throws {
        let pack = try XCTUnwrap(CameraPacks.bundled)
        XCTAssertEqual(pack.cameras.count, 127_264)
        let oriented = pack.cameras.filter { $0.bearing != nil }.count
        XCTAssertEqual(oriented, 118_504, "the DeFlock file tags 93 percent of its cameras")
        XCTAssertEqual(oriented + pack.cameras.filter { $0.bearing == nil }.count,
                       pack.cameras.count)
        XCTAssertTrue(pack.cameras.allSatisfy { camera in
            guard let bearing = camera.bearing else { return true }
            return bearing >= 0 && bearing < 360
        })
    }

    func testConesShareTheDotZoomGate() {
        XCTAssertEqual(MapLayers.cameraMinZoom, 13.5)
        XCTAssertEqual(CameraCones.minZoom, MapLayers.cameraMinZoom)
        XCTAssertFalse(CameraCones.visible(zoom: 13.49, layerOn: true))
        XCTAssertTrue(CameraCones.visible(zoom: 13.5, layerOn: true))
        XCTAssertFalse(CameraCones.visible(zoom: 17.0, layerOn: false),
                       "the ALPR switch still hides the cone with its dot")
    }

    func testWedgeShrinksOnTheGroundAtHighZoom() {
        XCTAssertGreaterThanOrEqual(CameraCones.groundLengthM(zoom: 13.5, latitudeDeg: 37.5),
                                    CameraCones.lengthM)
        XCTAssertEqual(CameraCones.groundLengthM(zoom: 17.0, latitudeDeg: 37.5),
                       CameraCones.lengthM, accuracy: 0.01)
        XCTAssertLessThan(CameraCones.groundLengthM(zoom: 20.0, latitudeDeg: 37.5),
                          CameraCones.lengthM)
        XCTAssertLessThan(CameraCones.groundLengthM(zoom: 22.0, latitudeDeg: 37.5), 5.0,
                          "a high zoom shows meters, not a screen-sized field of view")
    }

    func testReportLineCountsOrientedAndUnorientedCameras() {
        let previous = CameraPackDebug.cones
        defer { CameraPackDebug.cones = previous }
        CameraPackDebug.cones = "oriented=2 unoriented=1"
        let model = LayersModel(session: nil)
        XCTAssertTrue(model.debugLine.contains("oriented=2 unoriented=1"))
    }
}
