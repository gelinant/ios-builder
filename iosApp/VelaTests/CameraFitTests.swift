import CoreLocation
import UIKit
import XCTest
@testable import Vela

final class CameraFitTests: XCTestCase {
    private let size = CGSize(width: 390, height: 844)

    func testFlatFitPutsBothEndsInsideThePaddingAboveTheSheet() throws {
        let davis = CLLocationCoordinate2D(latitude: 38.5449, longitude: -121.7405)
        let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let inset = UIEdgeInsets(top: 0, left: 0, bottom: 422, right: 0)
        let padding = UIEdgeInsets(top: 170, left: 40, bottom: 452, right: 40)
        let camera = try XCTUnwrap(CameraFit.flatCamera(
            showing: [davis, sanFrancisco], size: size, contentInset: inset, padding: padding))
        XCTAssertEqual(camera.pitch, 0)
        XCTAssertEqual(camera.heading, 0)
        let projection = WebMapProjection(center: camera.centerCoordinate, zoom: camera.zoomLevel,
                                          bearing: 0, pitch: 0, size: size, inset: inset)
        let frame = CGRect(origin: .zero, size: size).inset(by: padding).insetBy(dx: -0.5, dy: -0.5)
        let a = projection.point(for: davis)
        let b = projection.point(for: sanFrancisco)
        XCTAssertTrue(frame.contains(a), "\(a) outside \(frame)")
        XCTAssertTrue(frame.contains(b), "\(b) outside \(frame)")
        // Tight on one side: the fit is not zoomed out further than it needs.
        let width = abs(a.x - b.x) / frame.width
        let height = abs(a.y - b.y) / frame.height
        XCTAssertGreaterThan(max(width, height), 0.99)
    }

    func testATallSheetStillLeavesACityWideFit() throws {
        // The transit chooser opens tall: the sheet plus the margins outgrow the screen.
        let padding = CameraFit.fitting(UIEdgeInsets(top: 170, left: 40, bottom: 768, right: 40),
                                        margin: CameraFit.endMargin, height: size.height)
        XCTAssertEqual(size.height - padding.top - padding.bottom, CameraFit.minFitHeight, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(padding.top, 0)
        XCTAssertGreaterThanOrEqual(padding.bottom, 0)
        let mission = CLLocationCoordinate2D(latitude: 37.7522, longitude: -122.4184)
        let ferry = CLLocationCoordinate2D(latitude: 37.7955, longitude: -122.3937)
        let camera = try XCTUnwrap(CameraFit.flatCamera(
            showing: [mission, ferry], size: size, contentInset: .zero, padding: padding))
        XCTAssertGreaterThan(camera.zoomLevel, 10, "a city trip zoomed out to \(camera.zoomLevel)")
        // Room to spare: nothing is taken back.
        let roomy = CameraFit.fitting(UIEdgeInsets(top: 170, left: 40, bottom: 300, right: 40),
                                      margin: CameraFit.endMargin, height: size.height)
        XCTAssertEqual(roomy.top, 194)
        XCTAssertEqual(roomy.bottom, 348)
    }

    func testFlatFitCapsTheZoomOfAShortRoute() throws {
        let start = CLLocationCoordinate2D(latitude: 38.5449, longitude: -121.7405)
        let end = CLLocationCoordinate2D(latitude: 38.5450, longitude: -121.7404)
        let camera = try XCTUnwrap(CameraFit.flatCamera(
            showing: [start, end], size: size, contentInset: .zero, padding: .zero))
        XCTAssertEqual(camera.zoomLevel, CameraFit.routeMaxZoom)
    }

    func testAreaZoomReadsPhotonAndGoogleKinds() {
        XCTAssertEqual(CameraFit.areaZoom(category: "City", placeType: nil), 11.5)
        XCTAssertEqual(CameraFit.areaZoom(category: "City in California", placeType: nil), 11.5)
        XCTAssertEqual(CameraFit.areaZoom(category: "State", placeType: nil), 7)
        XCTAssertEqual(CameraFit.areaZoom(category: nil, placeType: "SearchResult.TYPE_LOCALITY"), 12)
        XCTAssertEqual(CameraFit.areaZoom(category: nil, placeType: "SearchResult.TYPE_COUNTRY"), 5)
        XCTAssertNil(CameraFit.areaZoom(category: "State park", placeType: nil))
        XCTAssertNil(CameraFit.areaZoom(category: "Town hall", placeType: nil))
        XCTAssertNil(CameraFit.areaZoom(category: "Coffee shop", placeType: nil))
        XCTAssertNil(CameraFit.areaZoom(category: "Gas station",
                                        placeType: "SearchResult.TYPE_GAS_STATION"))
    }

    func testMainClusterDropsAFarNamesake() {
        let sacramento = CLLocationCoordinate2D(latitude: 38.5816, longitude: -121.4944)
        let davis = CLLocationCoordinate2D(latitude: 38.5449, longitude: -121.7405)
        let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let texas = CLLocationCoordinate2D(latitude: 29.76, longitude: -95.37)
        XCTAssertEqual(CameraFit.mainCluster([texas, sacramento, davis, sanFrancisco]), [1, 2])
        XCTAssertEqual(CameraFit.mainCluster([texas]), [0])
    }

    func testABareGeocodedRowIsFramedAsACity() {
        func row(_ address: String?, category: String? = nil, rating: Double? = nil) -> SearchRow {
            SearchRow(id: 0, stableId: "x", featureId: nil, name: "Sacramento", address: address,
                      rating: rating, reviewCount: nil, priceText: nil, category: category,
                      distanceMeters: nil, openNow: nil, statusText: nil, permanentlyClosed: false,
                      phone: nil, photoURL: nil, isSaved: false, latitude: 38.58, longitude: -121.49)
        }
        XCTAssertEqual(CameraFit.areaZoom(row("California")), 12)
        XCTAssertEqual(CameraFit.areaZoom(row(nil, category: "City")), 11.5)
        XCTAssertNil(CameraFit.areaZoom(row("1315 10th St, Sacramento, CA 95814")))
        XCTAssertNil(CameraFit.areaZoom(row("California", rating: 4.5)))
        XCTAssertNil(CameraFit.areaZoom(row("California", category: "Coffee shop")))
    }
}
