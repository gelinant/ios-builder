import Foundation
import VelaCore

/// Read-only adapters from the one SavedStore to App Intents and Spotlight. Recent searches and
/// recent places are deliberately absent: only explicitly saved content leaves Vela's stores.
enum VelaSavedContent {
    static var current: VelaIntentSnapshot {
        snapshot(AppGraph.session.saved.state.value)
    }

    static func snapshot(_ state: SavedState) -> VelaIntentSnapshot {
        var places = state.savedRows().map(reference)
        for list in state.lists {
            places.append(contentsOf: state.listPlaces(listId: list.id).map(reference))
        }
        return VelaIntentSnapshot(
            home: state.home.map(reference),
            work: state.work.map(reference),
            hasParking: state.parking != nil,
            savedPlaces: places)
    }

    static func entities(identifiers: [String]? = nil) -> [SavedPlaceAppEntity] {
        let references = current.savedPlaces
        if let identifiers {
            let wanted = Set(identifiers)
            return references.filter { wanted.contains($0.entityID) }.map(SavedPlaceAppEntity.init)
        }
        return references.map(SavedPlaceAppEntity.init)
    }

    private static func reference(_ row: SavedPlaceRow) -> VelaSavedReference {
        VelaSavedReference(
            placeID: row.placeId, listID: row.listId, name: row.name, address: row.address,
            latitude: row.lat, longitude: row.lng)
    }

    private static func reference(_ place: SavedPlace) -> VelaSavedReference {
        VelaSavedReference(
            placeID: place.id, listID: nil, name: place.name, address: place.address,
            latitude: place.lat, longitude: place.lng)
    }
}
