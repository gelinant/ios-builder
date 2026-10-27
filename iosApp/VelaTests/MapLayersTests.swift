import XCTest
@testable import Vela

/// The layer overlays must stay source-local: a downloaded offline style has no remote URL, and an
/// overlay that added one would silently break that promise. The Google rasters are the exception
/// and are gated off whenever a downloaded region owns the style.
final class MapLayersTests: XCTestCase {
    func testEveryOverlaySourceIsLocal() {
        XCTAssertFalse(MapLayers.sourceIdentifiers.isEmpty)
        for id in MapLayers.sourceIdentifiers {
            XCTAssertFalse(id.contains("http"), "remote source \(id)")
            XCTAssertFalse(id.contains("://"), "remote source \(id)")
        }
        for id in MapRasterLayers.remoteSourceIdentifiers {
            XCTAssertFalse(MapLayers.sourceIdentifiers.contains(id), "\(id) must stay out of the local list")
        }
    }

    func testSwitchChangesTheKotlinLayerState() {
        let layers = AppGraph.session.layers
        layers.setSwitch(key: "speed", on: true)
        XCTAssertTrue(layers.state.value.speedCameras)
        layers.setSwitch(key: "speed", on: false)
        XCTAssertFalse(layers.state.value.speedCameras)
    }

    func testTrafficAndSatelliteFollowTheAndroidKeys() {
        let layers = AppGraph.session.layers
        defer {
            layers.setSwitch(key: "traffic", on: false)
            layers.setSwitch(key: "satellite", on: false)
            layers.setPoiIconScale(scale: 1.0)
        }
        layers.setSwitch(key: "traffic", on: true)
        layers.setSwitch(key: "satellite", on: true)
        layers.setPoiIconScale(scale: 1.25)
        XCTAssertTrue(layers.state.value.trafficOn)
        XCTAssertTrue(layers.state.value.satelliteOn)
        XCTAssertEqual(layers.state.value.poiIconScale, 1.25, accuracy: 0.001)
    }

    func testRastersArePlannedOfflineAndPinnedToAndroidLimits() {
        let online = MapRasterLayers.Plan.make(traffic: true, satellite: true, offline: false)
        XCTAssertTrue(online.traffic)
        XCTAssertTrue(online.satellite)
        XCTAssertTrue(online.deep)

        let offline = MapRasterLayers.Plan.make(traffic: true, satellite: true, offline: true)
        XCTAssertEqual(offline, MapRasterLayers.Plan(), "a downloaded region must not fetch a raster")

        let session = AppGraph.session
        XCTAssertEqual(Int(session.rasterTrafficMaxZoom()), 16)
        XCTAssertEqual(Int(session.rasterSatelliteMaxZoom()), 19)
        XCTAssertEqual(Int(session.rasterSatelliteDeepMaxZoom()), 21)
        XCTAssertTrue(session.rasterTrafficUrl().hasPrefix("https://www.google.com/maps/vt/pb="))
        XCTAssertEqual(
            session.rasterSatelliteUrl(),
            "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}")
        XCTAssertEqual(session.rasterSatelliteDeepUrl(), "https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}")
    }

    func testGoogleTileRequestsCarryTheSafariIdentity() {
        let headers = AppGraph.session.rasterTileHeaders()
        let names = headers.map(\.name)
        XCTAssertTrue(names.contains("User-Agent"))
        XCTAssertTrue(names.contains("Referer"))
        XCTAssertTrue(headers.contains { $0.name == "User-Agent" && $0.value.contains("Safari") })
    }

    func testFuelLabelShowsThePencePrice() {
        let model = LayersModel(session: nil)
        let text = model.fuelTextForTest(brand: "Shell", e10: 145.9, e5: 152.0, b7p: 170.0)
        XCTAssertEqual(text, "Shell 145.9p")
    }
}
