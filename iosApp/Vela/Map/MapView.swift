import MapLibre
import QuartzCore
import SwiftUI
import UIKit

/// Full screen MapLibre map with the OpenFreeMap Liberty style.
struct MapView: UIViewRepresentable {
    let controller: MapController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> MLNMapView {
        // Before the map's HTTP session exists: the raster tile hook is a global configuration.
        MapTileNetwork.shared.install()
        let mapView = MLNMapView(frame: .zero, styleURL: controller.initialStyleURL())
        // M-1: the same ceiling as MapLibre Native's own hard limit.
        mapView.maximumPitch = CGFloat(Map3D.maximumPitch)
        mapView.minimumPitch = 0
        // G-2: the globe build paints the area outside the planet with the view's background. A
        // dark surround replaces the default white; Mercator keeps the same white surface.
        MapGlobeSurround.apply(to: mapView, projection: MapGlobeSettings.projection)
        let camera = LaunchOptions.current.camera
        mapView.setCenter(camera.center, zoomLevel: camera.zoom, animated: false)
        if let pitch = Self.launchPitch() {
            // One camera object, as the terrain spike recommends: setting the pitch after
            // `setCenter` on a separate call can drop the requested zoom.
            var tilted = mapView.camera
            tilted.pitch = pitch
            mapView.setCamera(tilted, animated: false)
        }
        context.coordinator.mapView = mapView
        Self.configureAccessibility(on: mapView, coordinator: context.coordinator)
        // The credit line in MapScreen replaces the logo; the info button stays for full attribution.
        mapView.logoView.isHidden = true
        mapView.delegate = context.coordinator
        controller.attach(mapView)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        // MapLibre installs its own single, double and two-finger taps, plus a zero-duration
        // quick-zoom long press. The controller recogniser must wait for every tap to fail and
        // must be allowed to recognise beside the quick zoom, otherwise one of the built-in
        // recognisers wins the touch and the app never sees a background tap.
        for case let other as UITapGestureRecognizer in mapView.gestureRecognizers ?? [] {
            tap.require(toFail: other)
        }
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        mapView.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = context.coordinator
        longPress.cancelsTouchesInView = false
        mapView.addGestureRecognizer(longPress)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.delegate = context.coordinator
        mapView.addGestureRecognizer(pan)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    /// `-VelaMapPitch <degrees>`: a deterministic start tilt for the 3D scenario, clamped to the
    /// 60 degree ceiling. It is a camera fixture, not a persisted setting.
    private static func launchPitch() -> CGFloat? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaMapPitch"),
              index + 1 < arguments.count,
              let value = Double(arguments[index + 1]) else { return nil }
        return CGFloat(min(max(value, 0), Map3D.maximumPitch))
    }

    /// The map is one accessibility element: its label, hint and rotor actions are the only ways
    /// VoiceOver can reach the two gestures that have no visible control. Kept free of MapLibre so
    /// MapAccessibilityTests can read the same attributes without loading a style.
    static func configureAccessibility(on view: UIView, coordinator: Coordinator) {
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "map"
        view.accessibilityLabel = "Map"
        view.accessibilityHint = "Use the rotor actions to select a feature or drop a pin at the map center."
        // Double-tap and hold passes touches through so VoiceOver users can pan the map directly.
        view.accessibilityTraits = [.allowsDirectInteraction]
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Select feature at map center",
                target: coordinator,
                selector: #selector(Coordinator.selectFeatureAtCenter(_:))),
            UIAccessibilityCustomAction(
                name: "Drop pin at map center",
                target: coordinator,
                selector: #selector(Coordinator.dropPinAtCenter(_:))),
        ]
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        private let controller: MapController
        weak var mapView: MLNMapView?
        /// A second tap inside this window is still the same gesture, not a second selection.
        private var lastTapAt = CACurrentMediaTime()
        private var lastTapPoint = CGPoint.zero

        init(controller: MapController) {
            self.controller = controller
        }

        @objc func selectFeatureAtCenter(_ action: UIAccessibilityCustomAction) -> Bool {
            guard let mapView else { return false }
            controller.handleTap(at: CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY))
            return true
        }

        @objc func dropPinAtCenter(_ action: UIAccessibilityCustomAction) -> Bool {
            guard let mapView else { return false }
            controller.handleLongPress(at: CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY))
            return true
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let point = gesture.location(in: view)
            // Count the recogniser before the double-tap window: a tap that the app deliberately
            // folds into the previous one is still a recogniser that fired.
            MapTapDebug.gesture(at: point)
            controller.noteTapSeen(recognizers: view.gestureRecognizers?.count ?? -1)
            let now = CACurrentMediaTime()
            let dx = point.x - lastTapPoint.x
            let dy = point.y - lastTapPoint.y
            if now - lastTapAt < 0.35, (dx * dx + dy * dy).squareRoot() < 8 {
                return
            }
            lastTapAt = now
            lastTapPoint = point
            // The map's own ornaments are the only controls above its drawing. A sheet or a
            // chrome button never sends this gesture to the map in the first place.
            if let map = view as? MLNMapView, let hit = view.hitTest(point, with: nil) {
                if hit === map.compassView || hit === map.attributionButton
                    || hit === map.scaleBar {
                    return
                }
            }
            controller.handleTap(at: point)
        }

        @objc func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view = gesture.view else { return }
            controller.handleLongPress(at: gesture.location(in: view))
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                controller.userPanned()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }


        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            controller.styleDidLoad(style)
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            controller.trackingModeDidChange(mode)
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            controller.regionDidChange()
        }

        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            if let coordinate = userLocation?.location?.coordinate {
                controller.userLocationDidUpdate(coordinate)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            controller.annotationView(for: annotation)
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            controller.didSelectAnnotation(annotation)
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            controller.canShowCallout(annotation)
        }
    }
}
