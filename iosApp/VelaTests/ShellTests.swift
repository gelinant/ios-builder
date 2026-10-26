import CoreLocation
import XCTest
@testable import Vela

final class ShellTests: XCTestCase {
    func testStyleIsOpenFreeMapLiberty() {
        XCTAssertEqual(MapDefaults.styleURL.absoluteString, "https://tiles.openfreemap.org/styles/liberty")
    }

    func testInitialCameraIsSanFrancisco() {
        let center = MapDefaults.initialCenter
        XCTAssertTrue(CLLocationCoordinate2DIsValid(center))
        XCTAssertEqual(center.latitude, 37.77, accuracy: 0.05)
        XCTAssertEqual(center.longitude, -122.42, accuracy: 0.05)
    }

    func testAttributionCreditsOpenFreeMapAndOpenStreetMap() {
        XCTAssertTrue(MapDefaults.attribution.contains("OpenFreeMap"))
        XCTAssertTrue(MapDefaults.attribution.contains("OpenStreetMap"))
    }

    func testInfoPlistDeclaresLocationAndBackgroundModes() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "app.vela.ios")
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Vela")
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        XCTAssertFalse(version.contains("$("), "version build setting not expanded")
        XCTAssertNotNil(info["NSLocationWhenInUseUsageDescription"] as? String)
        XCTAssertNotNil(info["NSLocationAlwaysAndWhenInUseUsageDescription"] as? String)
        let modes = try XCTUnwrap(info["UIBackgroundModes"] as? [String])
        XCTAssertTrue(modes.contains("location"))
        XCTAssertTrue(modes.contains("audio"))
    }

    func testVelaCoreShortensThroughCoreCommon() {
        XCTAssertEqual(VelaCoreCheck.shortRoadName("West Covell Boulevard"), "W Covell Blvd")
    }

    func testVelaCoreSelfCheckAnswersAcrossTheAsyncBridge() async {
        let line = await VelaCoreCheck.run()
        XCTAssertEqual(line, "VelaCore \(VelaCoreCheck.version): West Covell Boulevard -> W Covell Blvd")
    }
}
