import Foundation
import VelaCore

/// The lightweight sheet kept for a dropped pin or a POI without a confident Google match.
struct MapPoiCard: Equatable {
    let name: String
    let category: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let droppedPin: Bool
}

/// SwiftUI's side of the map-POI resolver. The normal Google match opens through `PlaceStore`.
final class MapPoiModel: ObservableObject {
    @Published private(set) var card: MapPoiCard?
    @Published private(set) var resolving = false
    @Published private(set) var googleUnavailable = false

    private let session: MapSession?
    private var observing: Task<Void, Never>?

    init(session: MapSession?) {
        self.session = session
    }

    func start() {
        guard let store = session?.mapPoi, observing == nil else { return }
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                self?.apply(state)
            }
        }
    }

    func tap(name: String, latitude: Double, longitude: Double, kind: String?) {
        session?.mapPoi.tap(name: name, lat: latitude, lng: longitude, kind: kind)
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

    private func apply(_ state: MapPoiState) {
        resolving = state.resolving
        googleUnavailable = state.googleUnavailable
        card = state.selected.map {
            MapPoiCard(
                name: $0.name, category: $0.category, address: $0.address,
                latitude: $0.location.lat, longitude: $0.location.lng,
                droppedPin: state.droppedPin)
        }
    }
}
