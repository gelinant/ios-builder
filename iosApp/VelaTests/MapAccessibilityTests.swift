import MapLibre
import XCTest
@testable import Vela

/// The map's label, hint and rotor actions are part of its accessibility element, which XCUITest
/// does not expose. These tests read the UIKit attributes the production map view gets, and check
/// that each rotor action is wired to the coordinator path behind the matching gesture.
final class MapAccessibilityTests: XCTestCase {
    func testMapElementExposesLabelHintAndRotorActions() {
        let controller = MapController(offline: nil)
        let coordinator = MapView.Coordinator(controller: controller)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        MapView.configureAccessibility(on: view, coordinator: coordinator)

        XCTAssertTrue(view.isAccessibilityElement, "the map is not an accessibility element")
        XCTAssertEqual(view.accessibilityIdentifier, "map")
        XCTAssertEqual(view.accessibilityLabel, "Map")
        XCTAssertFalse(view.accessibilityHint?.isEmpty ?? true, "the map has no hint")
        XCTAssertTrue(view.accessibilityTraits.contains(.allowsDirectInteraction),
                      "VoiceOver cannot pass a pan through to the map")

        let actions = view.accessibilityCustomActions ?? []
        XCTAssertEqual(actions.map(\.name), ["Select feature at map center", "Drop pin at map center"])
        for action in actions {
            XCTAssertTrue(action.target === coordinator, "\(action.name) targets another object")
        }
        XCTAssertEqual(actions.first?.selector,
                       #selector(MapView.Coordinator.selectFeatureAtCenter(_:)))
        XCTAssertEqual(actions.last?.selector,
                       #selector(MapView.Coordinator.dropPinAtCenter(_:)))
    }

    /// The rotor pin action must reach the same controller path as the long press gesture, at the
    /// map center rather than at a touch point.
    func testDropPinRotorActionUsesTheLongPressPathAtCenter() throws {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), styleURL: nil)
        let controller = MapController(offline: nil)
        controller.attach(mapView)
        let coordinator = MapView.Coordinator(controller: controller)
        coordinator.mapView = mapView
        MapView.configureAccessibility(on: mapView, coordinator: coordinator)

        var dropped: CLLocationCoordinate2D?
        controller.onMapLongPress = { dropped = $0 }
        let action = try XCTUnwrap(mapView.accessibilityCustomActions?.last)
        XCTAssertEqual(action.name, "Drop pin at map center")
        XCTAssertTrue(coordinator.dropPinAtCenter(action))

        let coordinate = try XCTUnwrap(dropped, "the rotor action did not reach the long press handler")
        let center = mapView.centerCoordinate
        XCTAssertEqual(coordinate.latitude, center.latitude, accuracy: 0.0001)
        XCTAssertEqual(coordinate.longitude, center.longitude, accuracy: 0.0001)
    }

    /// Selecting at the center goes through the same tap handler. An empty style has no feature,
    /// so no place may be reported.
    func testSelectFeatureRotorActionIsSafeWithoutAFeature() throws {
        let mapView = MLNMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), styleURL: nil)
        let controller = MapController(offline: nil)
        controller.attach(mapView)
        var picked = false
        controller.onPoiTap = { _, _, _ in picked = true }
        let coordinator = MapView.Coordinator(controller: controller)
        coordinator.mapView = mapView
        MapView.configureAccessibility(on: mapView, coordinator: coordinator)

        let action = try XCTUnwrap(mapView.accessibilityCustomActions?.first)
        XCTAssertEqual(action.name, "Select feature at map center")
        XCTAssertTrue(coordinator.selectFeatureAtCenter(action))
        XCTAssertFalse(picked, "a tap on an empty map selected a feature")
    }
}
