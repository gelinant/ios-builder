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
    let note: String?
    let icon: String?

    init(_ row: SavedPlaceRow) {
        id = row.id
        placeId = row.placeId
        listId = row.listId
        name = row.name
        address = row.address
        latitude = row.lat
        longitude = row.lng
        featureId = row.featureId
        note = row.note
        icon = row.icon
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
        note = nil
        icon = place.icon
    }
}

struct SavedListItem: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let color: UInt32
    let icon: String
    let alert: String?

    init(_ row: SavedListRow) {
        id = row.id
        name = row.name
        count = Int(row.count)
        color = UInt32(truncatingIfNeeded: row.color)
        icon = row.icon
        alert = row.alert
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
    @Published private(set) var importDone = 0
    @Published private(set) var importTotal = 0
    @Published private(set) var importMessage: String?
    @Published private(set) var pendingImport: SavedPendingImportItem?
    @Published private(set) var selectedSaved = false
    @Published private(set) var selectedListIds: Set<String> = []
    /// Debug label for the UI test: the last edit, including the tonal preview. Never user facing.
    @Published private(set) var feedback: String?

    private let session: MapSession?
    private let store: SavedStore?
    private var observing: Task<Void, Never>?
    private var placeObserving: Task<Void, Never>?
    private var googleFetch: WebFetchHandle?
    private var queuedGoogleLink: String?
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store?.renamePlace(placeId: item.placeId, name: trimmed, featureId: item.featureId)
    }

    func move(_ item: SavedPlaceItem, to listId: String) {
        if let from = item.listId {
            store?.moveListPlace(fromListId: from, placeId: item.placeId, toListId: listId)
        } else {
            store?.moveSavedPlace(placeId: item.placeId, toListId: listId)
        }
    }

    /// Bulk remove from one list, or from quick saves when [listId] is nil.
    func removePlaces(_ ids: Set<String>, in listId: String?) {
        guard !ids.isEmpty else { return }
        if let listId {
            store?.removeListPlaces(listId: listId, placeIds: Array(ids))
        } else {
            store?.removeSavedPlaces(placeIds: Array(ids))
        }
        feedback = "removed \(ids.count)"
        AppGraph.navHaptics.savedTick()
    }

    /// Bulk move from one list (nil for quick saves) to [toListId].
    func movePlaces(_ ids: Set<String>, from listId: String?, to toListId: String) {
        guard !ids.isEmpty else { return }
        if let listId {
            store?.moveListPlaces(fromListId: listId, placeIds: Array(ids), toListId: toListId)
        } else {
            store?.moveSavedPlaces(placeIds: Array(ids), toListId: toListId)
        }
        feedback = "moved \(ids.count)"
        AppGraph.navHaptics.savedTick()
    }

    /// Creates a list and moves the selection into it in one action.
    @discardableResult
    func createList(named name: String, move ids: Set<String>, from listId: String?) -> String {
        let id = createList(named: name)
        guard !id.isEmpty, !ids.isEmpty else { return id }
        movePlaces(ids, from: listId, to: id)
        return id
    }

    func reorderLists(_ orderedIds: [String]) {
        store?.reorderLists(orderedIds: orderedIds)
        AppGraph.navHaptics.savedTick()
    }

    func reorderPlaces(in listId: String, orderedIds: [String]) {
        store?.reorderListPlaces(listId: listId, orderedIds: orderedIds)
        AppGraph.navHaptics.savedTick()
    }

    func setNote(_ item: SavedPlaceItem, note: String?) {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        store?.setNote(placeId: item.placeId, note: trimmed?.isEmpty == true ? nil : trimmed, featureId: item.featureId)
        AppGraph.navHaptics.savedTick()
    }

    /// Saves the list editor's draft and returns its id, or nil when the store rejected the name.
    @discardableResult
    func saveList(id: String?, name: String, icon: String, color: UInt32, alert: String?) -> String? {
        if let id {
            let ok = store?.updateList(
                listId: id, name: name, icon: icon, color: Int64(truncatingIfNeeded: color), alert: alert) ?? false
            return ok ? id : nil
        }
        let created = createList(named: name)
        guard !created.isEmpty else { return nil }
        let ok = store?.updateList(
            listId: created, name: name, icon: icon, color: Int64(truncatingIfNeeded: color), alert: alert) ?? false
        return ok ? created : nil
    }

    func listNameProblem(_ name: String, excluding id: String?) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter a list name" }
        if trimmed.count > 40 { return "Keep the name under 40 characters" }
        if lists.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "A list with this name already exists"
        }
        return nil
    }

    /// Plays a list's drive-by sound once. The editor's preview and a place added to the list both
    /// call this; the tone frequencies come from the shared PassAlerts table, so no audio asset is
    /// added. "Say its name" speaks through the guidance voice.
    func playListSound(_ alert: String?, name: String) {
        guard let alert, !alert.isEmpty else { return }
        if SavedListSounds.shared.isName(sound: alert) {
            AppGraph.navVoice.speak(text: name, interrupt: true, ignoreMute: false)
        } else {
            SavedSoundPlayer.shared.play(notes: SavedListSounds.shared.notes(sound: alert) ?? [])
        }
        feedback = "sound \(alert)"
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
        let list = lists.first { $0.id == listId }
        // Android's list sound: adding a place to a list with one plays that list's sound, and the
        // same tone previews in the editor.
        playListSound(list?.alert, name: selected.name)
        AppGraph.navHaptics.savedTick()
        feedback = "added \(list?.name ?? "list") sound=\(list?.alert ?? "none")"
    }

    func removeSelected(from listId: String) {
        guard let selected else { return }
        store?.removeFromList(listId: listId, placeId: selected.id, featureId: selected.featureId)
        AppGraph.navHaptics.savedTick()
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

    /// Opens a shared Google Maps list through the hidden WebView. The store refuses before any
    /// request when "Use Vela without Google" is on or the link is not a Google host.
    ///
    /// The link sheet calls [requestGoogleLinkImport] and dismisses; the fetch starts from its
    /// `onDismiss`, because a merge/replace prompt requested while the sheet is still on screen is
    /// dropped by SwiftUI.
    func requestGoogleLinkImport(link: String) {
        queuedGoogleLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func runQueuedGoogleLinkImport() {
        guard let link = queuedGoogleLink else { return }
        queuedGoogleLink = nil
        startGoogleListImport(link: link)
    }

    private func startGoogleListImport(link: String) {
        guard let store else { return }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.beginGoogleListImport(link: trimmed) else { return }
        let handle = SavedGoogleListFetcher.shared.fetch(
            link: trimmed,
            onProgress: { done in store.googleListProgress(done: Int32(done)) },
            onResult: { [weak self] payload in
                store.setExternalImportCancel(cancel: nil)
                self?.googleFetch = nil
                if let payload {
                    store.finishGoogleListImport(payload: payload, link: trimmed)
                } else {
                    store.failGoogleListImport()
                }
            })
        googleFetch = handle
        store.setExternalImportCancel { [weak handle] in handle?.cancel() }
    }

    /// The document picker's KML/KMZ branch. The same store call the KML fixture uses.
    func importKml(data: Data, name: String) {
        _ = store?.importKmlFile(bytes: IosBytes.shared.toByteArray(data: data), name: name)
    }

    /// Writes a staged duplicate after the user chose Merge (true) or Replace (false).
    func resolvePendingImport(merge: Bool) {
        store?.commitPendingImport(mode: merge ? "MERGE" : "REPLACE")
    }

    func cancelPendingImport() {
        store?.cancelPendingImport()
    }

    func noteGoogleListUnavailable() {
        store?.noteGoogleListUnavailable()
    }

    var googleListAvailable: Bool { store?.googleListAvailable() ?? false }

    func cancelImport() {
        googleFetch?.cancel()
        googleFetch = nil
        store?.setExternalImportCancel(cancel: nil)
        store?.cancelImport()
    }

    /// One list as a shareable file. JSON keeps every field and the membership; GPX and KML are
    /// for other map apps and keep only names, coordinates and addresses.
    func exportList(_ list: SavedListItem, format: String = "JSON") -> SavedShareDocument? {
        guard let body = store?.exportList(listId: list.id, format: format) else { return nil }
        #if DEBUG
        SavedTestSupport.rememberExportForRoundtrip(body)
        #endif
        return try? SavedDocumentExport.document(
            body, baseName: "vela-list-\(list.name)", extension: format.lowercased())
    }

    func shareList(_ list: SavedListItem) -> SavedShareDocument? { exportList(list) }

    /// Every quick save in one file, or nil with none saved.
    func exportSaved(format: String) -> SavedShareDocument? {
        guard let body = store?.exportSaved(format: format) else { return nil }
        return try? SavedDocumentExport.document(
            body, baseName: "vela-saved-places", extension: format.lowercased())
    }

    /// Every list in one JSON file, or nil with no list.
    func exportAllLists() -> SavedShareDocument? {
        guard let body = store?.exportListsJson() else { return nil }
        return try? SavedDocumentExport.document(body, baseName: "vela-lists", extension: "json")
    }

    /// Quick saves and lists together, as two files in one share sheet: the same two documents
    /// Android's Settings screen writes, not a combined format neither app imports.
    func exportEverything() -> [SavedShareDocument] {
        [exportSaved(format: "JSON"), exportAllLists()].compactMap { $0 }
    }

    /// One place, quick-saved or from a list, in the chosen format.
    func exportPlace(_ item: SavedPlaceItem, format: String) -> SavedShareDocument? {
        guard let body = store?.exportPlace(
            listId: item.listId, placeId: item.placeId, format: format) else { return nil }
        return try? SavedDocumentExport.document(
            body, baseName: "vela-place-\(item.name)", extension: format.lowercased())
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
        importDone = Int(state.importDone)
        importTotal = Int(state.importTotal)
        importMessage = state.lastImport.flatMap(Self.importMessage)
        pendingImport = state.pendingImport.map(SavedPendingImportItem.init)
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
            var text = "\(result.count) place\(result.count == 1 ? "" : "s") imported"
            if result.lists > 1 {
                text += " into \(result.lists) lists"
            } else {
                text += " into \(result.name ?? "the list")"
            }
            if result.missed > 0 { text += "; \(result.missed) not found" }
            if result.needGoogle > 0 { text += "; \(result.needGoogle) need Google" }
            return text
        case "GOOGLE_DISABLED":
            return "Google list import needs Google; import a KML or KMZ file instead"
        case "LINK_INVALID":
            return "That is not a Google Maps list link"
        case "GOOGLE_UNREADABLE":
            return "That link did not show a shared Google list; nothing was imported"
        case "CANCELLED":
            return "Import canceled; completed places were kept"
        case "FAILED":
            return "Import failed; nothing was changed"
        default:
            return "Import finished"
        }
    }
}
