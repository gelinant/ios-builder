import Foundation
import VelaCore

struct SavedPlaceItem: Identifiable, Equatable {
    let id: String
    let placeId: String
    let listId: String?
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double
    let featureId: String?

    init(_ row: SavedPlaceRow) {
        id = row.id
        placeId = row.placeId
        listId = row.listId
        name = row.name
        address = row.address
        latitude = row.lat
        longitude = row.lng
        featureId = row.featureId
    }

    init(_ place: SavedPlace) {
        id = "saved:\(place.id)"
        placeId = place.id
        listId = nil
        name = place.name
        address = place.address
        latitude = place.lat
        longitude = place.lng
        featureId = nil
    }
}

struct SavedListItem: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let color: UInt32

    init(_ row: SavedListRow) {
        id = row.id
        name = row.name
        count = Int(row.count)
        color = UInt32(truncatingIfNeeded: row.color)
    }
}

struct RecentItem: Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String?
    let placeId: String?

    init(_ row: RecentRow) {
        id = row.id
        kind = row.kind
        title = row.title
        subtitle = row.subtitle
        placeId = row.placeId
    }
}

struct SavedRouteItem: Identifiable, Equatable {
    let id: String
    let name: String
    let mode: String
    let originLabel: String
    let destLabel: String
    let createdAt: Date

    init(_ row: SavedRouteRow) {
        id = row.id
        name = row.name
        mode = row.mode
        originLabel = row.originLabel
        destLabel = row.destLabel
        createdAt = Date(timeIntervalSince1970: row.createdAtSeconds)
    }
}

struct SavedMapMarker: Identifiable, Equatable {
    let id: String
    let placeId: String
    let listId: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let color: UInt32
    let parking: Bool

    init(_ row: SavedMarker) {
        id = row.id
        placeId = row.placeId
        listId = row.listId
        name = row.parking ? "Parked car" : row.name
        latitude = row.lat
        longitude = row.lng
        color = UInt32(truncatingIfNeeded: row.color)
        parking = row.parking
    }
}

struct ParkingItem: Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let date: Date
    fileprivate let row: ParkingRow

    init(_ row: ParkingRow) {
        id = row.id
        latitude = row.lat
        longitude = row.lng
        date = Date(timeIntervalSince1970: row.savedAtSeconds)
        self.row = row
    }

    static func == (a: ParkingItem, b: ParkingItem) -> Bool { a.id == b.id }
}

struct ShortcutItem: Equatable {
    let name: String
    let address: String?

    init?(_ place: SavedPlace?) {
        guard let place else { return nil }
        name = place.name
        address = place.address
    }
}

/// SwiftUI's mirror of the Kotlin saved facet. Main thread only, like the other map models.
final class SavedModel: ObservableObject {
    @Published private(set) var savedPlaces: [SavedPlaceItem] = []
    @Published private(set) var lists: [SavedListItem] = []
    @Published private(set) var recents: [RecentItem] = []
    @Published private(set) var routes: [SavedRouteItem] = []
    @Published private(set) var markers: [SavedMapMarker] = []
    @Published private(set) var home: ShortcutItem?
    @Published private(set) var work: ShortcutItem?
    @Published private(set) var parking: ParkingItem?
    @Published private(set) var parkingHistory: [ParkingItem] = []
    @Published private(set) var importing = false
    @Published private(set) var importMessage: String?
    @Published private(set) var selectedSaved = false
    @Published private(set) var selectedListIds: Set<String> = []

    private let session: MapSession?
    private let store: SavedStore?
    private var observing: Task<Void, Never>?
    private var placeObserving: Task<Void, Never>?
    private var snapshot: SavedState?
    private var selected: Place?

    init(session: MapSession?) {
        self.session = session
        store = session?.saved
    }

    func start() {
        guard let session, let store else { return }
        if observing == nil {
            observing = Task { @MainActor [weak self] in
                for await state in store.state {
                    self?.apply(state)
                }
            }
        }
        if placeObserving == nil {
            placeObserving = Task { @MainActor [weak self] in
                for await state in session.place.state {
                    self?.selected = state.selected
                    self?.updateSelection()
                }
            }
        }
    }

    func toggleSelected() {
        guard let selected else { return }
        _ = store?.toggleSave(place: selected)
    }

    func remove(_ item: SavedPlaceItem) {
        if let listId = item.listId {
            store?.removeFromList(listId: listId, placeId: item.placeId, featureId: item.featureId)
        } else {
            store?.removeSaved(placeId: item.placeId)
        }
    }

    func rename(_ item: SavedPlaceItem, to name: String) {
        store?.renamePlace(placeId: item.placeId, name: name, featureId: item.featureId)
    }

    func move(_ item: SavedPlaceItem, to listId: String) {
        if let from = item.listId {
            store?.moveListPlace(fromListId: from, placeId: item.placeId, toListId: listId)
        } else {
            store?.moveSavedPlace(placeId: item.placeId, toListId: listId)
        }
    }

    @discardableResult
    func createList(named name: String) -> String {
        store?.createList(name: name) ?? ""
    }

    @discardableResult
    func createList(named name: String, addPlace: Bool) -> String {
        let id = createList(named: name)
        if addPlace && !id.isEmpty { addSelected(to: id) }
        return id
    }

    func renameList(_ id: String, to name: String) {
        store?.renameList(listId: id, name: name)
    }

    func deleteList(_ id: String) {
        store?.deleteList(listId: id)
    }

    func moveList(_ id: String, by delta: Int) {
        store?.moveList(listId: id, delta: Int32(delta))
    }

    func addSelected(to listId: String) {
        guard let selected else { return }
        store?.addToList(listId: listId, place: selected)
    }

    func removeSelected(from listId: String) {
        guard let selected else { return }
        store?.removeFromList(listId: listId, placeId: selected.id, featureId: selected.featureId)
    }

    func setSelectedShortcut(home: Bool) {
        guard let selected else { return }
        store?.setShortcutNamed(name: home ? "HOME" : "WORK", place: selected)
    }

    func clearShortcut(home: Bool) {
        store?.clearShortcutNamed(name: home ? "HOME" : "WORK")
    }

    func saveParkingAtSelected() {
        guard let selected else { return }
        store?.saveParking(place: selected)
    }

    @discardableResult
    func saveParkingHere() -> Bool {
        store?.saveParkingAtMyLocation() ?? false
    }

    func clearParking() { store?.clearParking() }
    func restoreParking(_ item: ParkingItem) { store?.restoreParking(row: item.row) }
    func deleteParking(_ item: ParkingItem) { store?.deleteParking(row: item.row) }
    func clearParkingHistory() { store?.clearParkingHistory() }

    func removeRecent(_ item: RecentItem) {
        if item.kind == "search" {
            store?.removeRecentSearch(query: item.title)
        } else if let placeId = item.placeId {
            store?.removeRecentPlace(placeId: placeId)
        }
    }

    func clearRecents() { store?.clearRecents() }

    func renameRoute(_ id: String, to name: String) {
        store?.renameRoute(id: id, name: name)
    }

    func deleteRoute(_ id: String) {
        store?.deleteRoute(id: id)
    }

    func open(_ item: SavedPlaceItem) {
        session?.openSavedPlace(listId: item.listId, placeId: item.placeId)
    }

    func open(_ item: RecentItem) {
        guard let placeId = item.placeId else { return }
        session?.openSavedPlace(listId: nil, placeId: placeId)
    }

    func open(_ item: SavedRouteItem) {
        session?.openSavedRoute(id: item.id)
    }

    func open(_ marker: SavedMapMarker) {
        guard !marker.parking else { return }
        session?.openSavedPlace(listId: marker.listId, placeId: marker.placeId)
    }

    /// Resolves a deep link against the current store, even before the SwiftUI mirror's first yield.
    func place(placeId: String, listId: String?) -> SavedPlaceItem? {
        guard let state = store?.state.value ?? snapshot else { return nil }
        if let listId {
            return state.listPlaces(listId: listId).first { $0.placeId == placeId }.map(SavedPlaceItem.init)
        }
        return state.savedRows().first { $0.placeId == placeId }.map(SavedPlaceItem.init)
    }

    /// Home and Work remain openable after their original place leaves quick saves and recents.
    @discardableResult
    func openShortcut(home: Bool) -> SavedPlaceItem? {
        guard let state = store?.state.value ?? snapshot,
              let place = home ? state.home : state.work else { return nil }
        session?.place.select(p: place.toPlace())
        return SavedPlaceItem(place)
    }

    /// Parking is not a quick-saved id, so it opens through PlaceStore's normal lightweight place.
    @discardableResult
    func openParking() -> ParkingItem? {
        guard let row = store?.state.value.parkingRow(),
              let place = store?.parkingPlace(name: "Parked car") else { return nil }
        session?.place.select(p: place)
        return ParkingItem(row)
    }

    func shareSelectedUrl() -> String? { session?.shareSelectedPlaceUrl() }

    func importFile(text: String, name: String) {
        store?.importFile(text: text, name: name)
    }

    func cancelImport() { store?.cancelImport() }

    func shareList(_ list: SavedListItem) -> SavedShareDocument? {
        guard let json = store?.exportListJson(listId: list.id) else { return nil }
        return try? SavedDocumentExport.json(json, listName: list.name)
    }

    func locationChanged(latitude: Double, longitude: Double) {
        store?.onLocation(lat: latitude, lng: longitude)
    }

    func mapCenterChanged(latitude: Double, longitude: Double) {
        store?.onMapCenter(lat: latitude, lng: longitude)
    }

    func places(in listId: String) -> [SavedPlaceItem] {
        snapshot?.listPlaces(listId: listId).map(SavedPlaceItem.init) ?? []
    }

    func parkingAge(_ item: ParkingItem) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.date, relativeTo: Date())
    }

    private func apply(_ state: SavedState) {
        snapshot = state
        savedPlaces = state.savedRows().map(SavedPlaceItem.init)
        lists = state.listRows().map(SavedListItem.init)
        recents = state.recentRows().map(RecentItem.init)
        routes = state.routeRows().map(SavedRouteItem.init)
        markers = state.markers().map(SavedMapMarker.init)
        home = ShortcutItem(state.home)
        work = ShortcutItem(state.work)
        parking = state.parkingRow().map(ParkingItem.init)
        parkingHistory = state.parkingRows().map(ParkingItem.init)
        importing = state.importing
        importMessage = state.lastImport.flatMap(Self.importMessage)
        updateSelection()
    }

    private func updateSelection() {
        guard let selected, let snapshot else {
            selectedSaved = false
            selectedListIds = []
            return
        }
        let listIds = snapshot.lists.filter { list in
            list.places.contains { row in
                row.id == selected.id || (selected.featureId != nil && row.featureId == selected.featureId)
            }
        }.map(\.id)
        selectedListIds = Set(listIds)
        selectedSaved = snapshot.saved.contains { $0.id == selected.id } || !listIds.isEmpty
    }

    private static func importMessage(_ result: SavedImport) -> String {
        switch result.kindName {
        case "ADDED":
            return "\(result.count) place\(result.count == 1 ? "" : "s") imported"
        case "NOTHING_NEW":
            return "Nothing new to import"
        case "WRONG_FORMAT":
            return result.name.map { "Cannot import this \($0) file" } ?? "Cannot import this file"
        case "UNREADABLE":
            return "The file could not be read"
        case "BUSY":
            return "Another import is still running"
        case "LIST_ADDED":
            var text = "\(result.count) place\(result.count == 1 ? "" : "s") imported into \(result.name ?? "the list")"
            if result.missed > 0 { text += "; \(result.missed) not found" }
            if result.needGoogle > 0 { text += "; \(result.needGoogle) need Google" }
            return text
        case "CANCELLED":
            return "Import canceled; completed places were kept"
        default:
            return "Import finished"
        }
    }
}
