import CoreLocation
import MapLibre
import XCTest
@testable import Vela

/// MAP-TAP's acceptance: the set of identifiers the layer classes can draw and the set of
/// handlers the registry holds are the same. A future layer that is added to a class without a
/// rule fails here before it can become a silent dead spot on the map.
final class MapTapRegistryTests: XCTestCase {
    func testDrawnSectionIdentifiersEqualRegisteredHandlers() {
        XCTAssertFalse(MapTapRegistry.drawnStyleIdentifiers.isEmpty,
                       "the drawn set must not be empty")
        XCTAssertEqual(MapTapRegistry.drawnStyleIdentifiers,
                       MapTapRegistry.registeredStyleIdentifiers,
                       "a drawn style layer has no tap handler")
    }

    func testDynamicFamiliesAreRegistered() {
        XCTAssertEqual(MapTapRegistry.drawnDynamicPrefixes,
                       MapTapRegistry.registeredDynamicPrefixes)
        XCTAssertNotNil(MapTapRegistry.rule(for: "vela-transit-line-3"))
        XCTAssertNotNil(MapTapRegistry.rule(for: "vela-saved-shape-2-line"))
        XCTAssertNotNil(MapTapRegistry.rule(for: "vela-saved-shape-2-fill"))
        XCTAssertNotNil(MapTapRegistry.rule(for: "vela-saved-shape-2-label"))
    }

    func testEveryAnnotationChannelHasAHandler() {
        XCTAssertFalse(MapTapRegistry.annotationChannels.isEmpty)
        XCTAssertEqual(MapTapRegistry.drawnAnnotationChannels,
                       Set(MapTapRegistry.annotationChannels.keys))
    }

    func testRequiredKindsRouteToTheirHandler() {
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-poi")?.handler, .place)
        XCTAssertEqual(MapTapRegistry.rule(for: "poi_r7")?.handler, .place)
        XCTAssertEqual(MapTapRegistry.rule(for: "poi_transit")?.handler, .place)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-speed")?.handler, .camera)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-alpr")?.handler, .camera)
        XCTAssertEqual(MapTapRegistry.rule(for: MapLayers.alprConeLayerId)?.handler, .camera)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-aircraft")?.handler, .aircraft)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-maritime-ship-dots")?.handler, .ship)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-wiki-circles")?.handler, .wiki)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-wiki-labels")?.handler, .wiki)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-transit-line-0")?.handler, .transitStop)
        XCTAssertEqual(MapTapRegistry.rule(for: "vela-saved-shape-0-line")?.handler, .savedShape)
    }

    func testRastersAreRegisteredAndInert() {
        for identifier in MapRasterLayers.layerIdentifiers {
            XCTAssertEqual(MapTapRegistry.rule(for: identifier)?.handler, MapTapHandler.none,
                           "\(identifier) must be registered and do nothing")
        }
    }

    func testAuditAcceptsTheDeclaredSetAndReportsAFutureLayer() {
        XCTAssertTrue(
            MapTapRegistry.audit(identifiers: Array(MapTapRegistry.drawnStyleIdentifiers)).isEmpty)
        XCTAssertEqual(MapTapRegistry.audit(identifiers: ["vela-future-layer"]),
                       ["vela-future-layer"])
        XCTAssertNil(MapTapRegistry.rule(for: "vela-future-layer"),
                     "the fallback is separate from the declared registry")
        XCTAssertEqual(MapTapRegistry.fallbackRule(for: "vela-future-layer")?.handler,
                       .layerFeature,
                       "an unregistered app layer is still tappable through the fallback")
    }

    func testPointFeatureBecomesATypedCameraEvent() {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: 37.5, longitude: -121.5)
        feature.attributes = ["bearing": NSNumber(value: 90)]
        let rule = try! XCTUnwrap(MapTapRegistry.rule(for: "vela-alpr"))
        let hit = MapTapHit(rule: rule, feature: feature, layerIndex: 0)
        let event = MapTapRegistry.event(
            for: hit, in: nil, point: .zero)
        XCTAssertEqual(event, .camera(kind: "Plate camera", latitude: 37.5, longitude: -121.5,
                                      bearing: 90))
    }

    func testNamedPlaceKeepsItsOsmIdAndKind() {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: 38.5, longitude: -121.7)
        feature.attributes = [
            "name": "Cafe",
            "class": "restaurant",
            "osm_id": "node/1",
        ]
        let rule = try! XCTUnwrap(MapTapRegistry.rule(for: "poi_r7"))
        let hit = MapTapHit(rule: rule, feature: feature, layerIndex: 0)
        let event = MapTapRegistry.event(
            for: hit, in: nil, point: .zero)
        XCTAssertEqual(event, .place(name: "Cafe", latitude: 38.5, longitude: -121.7,
                                     kind: "restaurant", osmId: "node/1"))
    }

    func testFeatureWithoutAnIdStillProducesItsKindAndCoordinate() {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: 38.5, longitude: -121.7)
        let rule = try! XCTUnwrap(MapTapRegistry.rule(for: "vela-aircraft"))
        let hit = MapTapHit(rule: rule, feature: feature, layerIndex: 0)
        let event = MapTapRegistry.event(
            for: hit, in: nil, point: .zero)
        XCTAssertEqual(event, .aircraft(hex: "", callsign: nil,
                                        latitude: 38.5, longitude: -121.7))
    }

    func testSavedShapeCarriesItsListAndIndex() {
        let feature = MLNPointFeature()
        feature.coordinate = CLLocationCoordinate2D(latitude: 37.7, longitude: -122.4)
        feature.attributes = [
            "listId": "list:test",
            "index": NSNumber(value: 2),
            "name": "Route",
            "closed": NSNumber(value: false),
        ]
        let rule = try! XCTUnwrap(MapTapRegistry.rule(for: "vela-saved-shape-2-line"))
        let hit = MapTapHit(rule: rule, feature: feature, layerIndex: 0)
        let event = MapTapRegistry.event(
            for: hit, in: nil, point: .zero)
        XCTAssertEqual(event, .savedShape(listId: "list:test", index: 2, name: "Route",
                                          closed: false, latitude: 37.7, longitude: -122.4))
    }
}
