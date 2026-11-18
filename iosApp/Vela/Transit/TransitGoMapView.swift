import SwiftUI
import UIKit
import VelaCore

/// GO's map region with its own model. It hands the vehicle the rail should follow back to the
/// screen, so the rail and the map show the same estimate.
struct TransitGoMapSection: View {
    @StateObject private var map: TransitGoMapModel
    let state: TransitGoState
    let onHint: (TransitGoVehicleHint?) -> Void

    init(trip: TransitItinerary, budget: TransitRequestBudget?, state: TransitGoState,
         onHint: @escaping (TransitGoVehicleHint?) -> Void) {
        var fixture: ((Int64) -> [TransitVehicle])?
        #if DEBUG
        // The GO scenarios and the recorded transit fixture never ask the feed: two live K
        // stretches around the clock run through the production interpolation instead.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-VelaTransitGoTest") || LaunchOptions.current.transitFixture {
            fixture = { now in TransitGoMapFixtures.shared.vehicles(trip: trip, nowEpochSec: now) }
        }
        #endif
        _map = StateObject(wrappedValue: TransitGoMapModel(trip: trip, budget: budget, fixture: fixture))
        self.state = state
        self.onHint = onHint
    }

    var body: some View {
        TransitGoMapRegion(model: map)
            .onAppear {
                map.update(state: state)
                onHint(map.vehicleHint)
            }
            .onDisappear { map.stop() }
            .onChange(of: state) { _, next in
                map.update(state: next)
                onHint(map.vehicleHint)
            }
            .onChange(of: map.vehicleCount) { _, _ in onHint(map.vehicleHint) }
    }
}

/// The map region of GO: a second MapLibre GL JS map, separate from the main map, as the trip
/// detail map already is. It is flat and north up, without terrain, so a glance reads like a
/// plan; pans and pinches pause the camera rule of `TransitGoMapModel`.
struct TransitGoMapRegion: View {
    @ObservedObject var model: TransitGoMapModel

    var body: some View {
        TransitGoMapView(model: model)
            .overlay(alignment: .topTrailing) {
                if model.paused {
                    Button {
                        model.recenter()
                    } label: {
                        Label(VelaL10n.text("transit_go_recenter"), systemImage: "location.viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: Design.Size.hitTarget)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .padding(Design.Spacing.s)
                    .accessibilityIdentifier("transit-go-map-recenter")
                }
            }
            .overlay(alignment: .bottomLeading) {
                // Every dot is an estimate; the map says so in words, not only in the panel.
                if model.vehicleCount > 0 {
                    Text(VelaL10n.text("transit_estimated"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(Design.Spacing.s)
                        .accessibilityLabel(VelaL10n.text("transit_go_map_vehicles_estimated"))
                        .accessibilityIdentifier("transit-go-map-estimated")
                }
            }
            .overlay(alignment: .topLeading) {
                #if DEBUG
                Text(model.debugLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1, alignment: .topLeading)
                    .accessibilityIdentifier("transit-go-map-debug")
                    .allowsHitTesting(false)
                #endif
            }
            .clipped()
    }
}

/// The map view itself. The model is its delegate and owns every layer and annotation.
private struct TransitGoMapView: UIViewRepresentable {
    let model: TransitGoMapModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapDefaults.styleURL)
        mapView.logoView.isHidden = true
        mapView.terrainEnabled = false
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = true
        mapView.isAccessibilityElement = true
        mapView.accessibilityIdentifier = "transit-go-map"
        mapView.accessibilityLabel = VelaL10n.text("transit_go_map_label")
        for recognizer in [UIPanGestureRecognizer(), UIPinchGestureRecognizer()] as [UIGestureRecognizer] {
            recognizer.addTarget(context.coordinator, action: #selector(Coordinator.moved(_:)))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = context.coordinator
            mapView.addGestureRecognizer(recognizer)
        }
        model.attach(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: TransitGoMapModel

        init(model: TransitGoMapModel) { self.model = model }

        @objc func moved(_ recognizer: UIGestureRecognizer) {
            if recognizer.state == .began || recognizer.state == .changed {
                model.userMovedMap()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
