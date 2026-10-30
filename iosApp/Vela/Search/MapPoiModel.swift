import CoreLocation
import Foundation
import VelaCore

/// The lightweight sheet kept for a dropped pin or a tapped POI without a confident Google match.
struct MapPoiCard: Equatable {
    let id: String
    let name: String
    let category: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let droppedPin: Bool
    /// Distance from the user's last fix, when the app has one; nil hides the line.
    let distanceMeters: Double?
    /// `exact`, `near` or `fallback`, for the debug line only.
    let match: String
    let googleSearchable: Bool
    let googleSearchFoundNothing: Bool
}

/// SwiftUI's side of the map-POI resolver. A confident Google match opens through `PlaceStore`;
/// a miss keeps this sheet, built from the tapped vector label alone.
final class MapPoiModel: ObservableObject {
    @Published private(set) var card: MapPoiCard?
    @Published private(set) var resolving = false
    @Published private(set) var googleUnavailable = false

    private let session: MapSession?
    private let location = CLLocationManager()
    private var observing: Task<Void, Never>?
    private var fixtureOpened = false

    init(session: MapSession?) {
        self.session = session
    }

    func start() {
        openFixtureIfAsked()
        guard let store = session?.mapPoi, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func tap(name: String, latitude: Double, longitude: Double, kind: String?) {
        session?.mapPoi.tap(
            name: name, lat: latitude, lng: longitude, kind: kind, from: userFix())
    }

    func longPress(latitude: Double, longitude: Double) {
        session?.mapPoi.longPress(lat: latitude, lng: longitude)
    }

    func directions() {
        session?.openMapPoiDirections()
    }

    func close() {
        session?.mapPoi.close()
    }

    /// The scale position of a tapped POI, taken from the map's already-granted location. A
    /// missing fix leaves the distance line out rather than inventing one.
    private func userFix() -> LatLng? {
        guard let fix = location.location else { return nil }
        return LatLng(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
    }

    /// Debug scenario only: a fixed answer set drives the same decision as a real tap, so the UI
    /// test needs no network. Production launches carry no such argument.
    private func openFixtureIfAsked() {
        #if DEBUG
        guard !fixtureOpened else { return }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-VelaMapPoiFixture"),
              index + 1 < arguments.count else { return }
        let scenario = arguments[index + 1].trimmingCharacters(in: .whitespaces)
        guard ["exact", "fallback"].contains(scenario) else { return }
        fixtureOpened = true
        session?.mapPoi.tapFixture(scenario: scenario)
        #endif
    }

    private func apply(_ state: MapPoiState) {
        resolving = state.resolving
        googleUnavailable = state.googleUnavailable
        card = state.selected.map {
            MapPoiCard(
                id: $0.id,
                name: $0.name, category: $0.category, address: $0.address,
                latitude: $0.location.lat, longitude: $0.location.lng,
                droppedPin: state.droppedPin,
                distanceMeters: $0.distanceMeters?.doubleValue,
                match: state.match,
                googleSearchable: state.googleSearchable,
                googleSearchFoundNothing: state.googleSearchFoundNothing)
        }
    }
}

/// The OpenStreetMap sheet's actions: save through the shared store, share the OSM point, and the
/// explicit Google lookup. Kept out of the view so the scenario can read the same paths.
final class MapPoiActions: ObservableObject {
    @Published private(set) var saved = false

    private let session: MapSession?

    init(session: MapSession?) {
        self.session = session
    }

    func refresh(_ card: MapPoiCard) {
        saved = session?.saved.contains(placeId: card.id, featureId: nil) ?? false
    }

    /// Saves the map label itself; the shared store keeps its name, point and category.
    func toggleSave(_ card: MapPoiCard) {
        guard let place = session?.mapPoi.state.value.selected else { return }
        saved = session?.saved.toggleSave(place: place) ?? false
    }

    func searchGoogle() {
        session?.mapPoi.searchGoogle()
    }

    /// The OpenStreetMap point the label came from. A vector-tile tap carries no object id, so
    /// the point is the honest reference rather than an invented node.
    func share(_ card: MapPoiCard) -> VelaSharePayload {
        let point = String(format: "%.6f/%.6f", card.latitude, card.longitude)
        let link = "https://www.openstreetmap.org/?mlat=\(String(format: "%.6f", card.latitude))"
            + "&mlon=\(String(format: "%.6f", card.longitude))#map=19/\(point)"
        let coordinates = String(format: "%.5f, %.5f", card.latitude, card.longitude)
        return VelaSharePayload(subject: card.name, text: "\(card.name)\n\(coordinates)", link: link)
    }
}
