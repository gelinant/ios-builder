package app.vela.ios.saved

import app.vela.core.data.ImportResult
import app.vela.core.data.MapDataSource
import app.vela.core.data.MyMapKml
import app.vela.core.data.NoGoogle
import app.vela.core.data.ParkingStore
import app.vela.core.data.PlaceImport
import app.vela.core.data.PlaceListStore
import app.vela.core.data.PlaceShortcutStore
import app.vela.core.data.RecentPlace
import app.vela.core.data.RecentPlaceStore
import app.vela.core.data.RecentQuery
import app.vela.core.data.RecentSearchStore
import app.vela.core.data.SavedPlaceStore
import app.vela.core.data.SavedRouteStore
import app.vela.core.data.TakeoutCsv
import app.vela.core.data.google.PolylineCodec
import app.vela.core.data.google.parse.EntityListParser
import app.vela.core.data.importTarget
import app.vela.core.model.LatLng
import app.vela.core.model.ListPlace
import app.vela.core.model.MapShape
import app.vela.core.model.ParkedSpot
import app.vela.core.model.Place
import app.vela.core.model.PlaceList
import app.vela.core.model.SavedPlace
import app.vela.core.model.SavedRoute
import app.vela.core.model.ShortcutKind
import app.vela.core.nav.PassAlerts
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueStores
import app.vela.core.util.Fmt
import app.vela.core.util.UrlCodec
import app.vela.ios.place.PlaceStore
import app.vela.ios.route.RouteState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

private val DEFAULT_SAVED_COLOR = 0xFF1A73E8.toInt()
private val PARKING_MARKER_COLOR = 0xFF5F6368.toInt()
private const val DEFAULT_LIST_COLOR = 0xFF1A73E8L

/** One parsed list waiting to be written; [sourceId] is what a re-import matches. */
private data class SavedImportDraft(
    val title: String,
    val description: String?,
    val places: List<ListPlace>,
    val shapes: List<MapShape>,
    val sourceId: String,
    val color: Long,
    val listId: String = "",
    val existingId: String? = null,
)

/** The saved places facet's persistent state. The seven common stores own their Android keys. */
data class SavedState(
    val saved: List<SavedPlace> = emptyList(),
    val lists: List<PlaceList> = emptyList(),
    val home: SavedPlace? = null,
    val work: SavedPlace? = null,
    val parking: ParkedSpot? = null,
    val parkingHistory: List<ParkedSpot> = emptyList(),
    val savedRoutes: List<SavedRoute> = emptyList(),
    val recentSearches: List<RecentQuery> = emptyList(),
    val recentPlaces: List<RecentPlace> = emptyList(),
    val importing: Boolean = false,
    val importDone: Int = 0,
    val importTotal: Int = 0,
    val lastImport: SavedImport? = null,
    /** Parsed but unwritten: a duplicate import waits for the user's merge or replace. */
    val pendingImport: SavedPendingImport? = null,
) {
    fun savedRows(): List<SavedPlaceRow> = saved.map { SavedPlaceRow.of(it) }

    fun listRows(): List<SavedListRow> = lists.map {
        SavedListRow(it.id, it.name, it.places.size, it.color.toInt(), it.icon, it.alert)
    }

    fun listPlaces(listId: String): List<SavedPlaceRow> =
        lists.firstOrNull { it.id == listId }?.places.orEmpty().map { SavedPlaceRow.of(it, listId) }

    /** Recent queries and places in one chronological list, newest first. */
    fun recentRows(): List<RecentRow> =
        (recentSearches.map { RecentRow("q:${it.query}", "search", it.query, null, null, it.at) } +
            recentPlaces.map { RecentRow("p:${it.place.id}", "place", it.place.name, it.place.address, it.place.id, it.at) })
            .sortedByDescending { it.atMillis }

    fun routeRows(): List<SavedRouteRow> = savedRoutes.map {
        SavedRouteRow(it.id, it.name, it.mode, it.originLabel, it.destLabel, it.createdAt / 1000.0)
    }

    fun parkingRow(): ParkingRow? = parking?.let { ParkingRow.of(it) }

    fun parkingRows(): List<ParkingRow> = parkingHistory.map { ParkingRow.of(it) }

    /**
     * The rows that App Intents and Spotlight publish: quick saves first, then every list entry.
     * [key] carries the list for a list entry so the same place in two lists stays two distinct
     * records. It is derived from the stored rows, never cached, so a rename, move or removal
     * changes the payload on the same state yield that the indexer observes.
     */
    fun indexRows(): List<SavedIndexRow> = buildList {
        saved.forEach { p ->
            add(SavedIndexRow("saved:${p.id}", p.id, null, p.name, p.address, p.lat, p.lng))
        }
        lists.forEach { list ->
            list.places.forEach { p ->
                add(SavedIndexRow("list:${list.id}:${p.id}", p.id, list.id, p.name, p.address, p.lat, p.lng))
            }
        }
    }

    /** Quick-saved places and every list entry, plus the parking spot, for the map. */
    fun markers(): List<SavedMarker> = buildList {
        saved.forEach { p -> add(SavedMarker("saved:${p.id}", p.id, null, p.name, p.lat, p.lng, DEFAULT_SAVED_COLOR, false)) }
        lists.forEach { list ->
            list.places.forEach { p ->
                add(SavedMarker("list:${list.id}:${p.id}", p.id, list.id, p.name, p.lat, p.lng, list.color.toInt(), false))
            }
        }
        parking?.let { p -> add(SavedMarker("parking", "parking", null, "", p.lat, p.lng, PARKING_MARKER_COLOR, true)) }
    }
}

data class SavedPlaceRow(
    val id: String,
    val placeId: String,
    val listId: String?,
    val name: String,
    val address: String?,
    val lat: Double,
    val lng: Double,
    val featureId: String?,
    val note: String? = null,
    val icon: String? = null,
) {
    companion object {
        fun of(p: SavedPlace): SavedPlaceRow =
            SavedPlaceRow("saved:${p.id}", p.id, null, p.name, p.address, p.lat, p.lng, null, icon = p.icon)

        fun of(p: ListPlace, listId: String): SavedPlaceRow =
            SavedPlaceRow("list:$listId:${p.id}", p.id, listId, p.name, p.address, p.lat, p.lng, p.featureId, p.note, p.icon)
    }
}

data class SavedListRow(
    val id: String,
    val name: String,
    val count: Int,
    val color: Int,
    val icon: String = "bookmark",
    val alert: String? = null,
)

data class SavedIndexRow(
    val key: String,
    val placeId: String,
    val listId: String?,
    val name: String,
    val address: String?,
    val lat: Double,
    val lng: Double,
)

data class RecentRow(
    val id: String,
    val kind: String,
    val title: String,
    val subtitle: String?,
    val placeId: String?,
    val atMillis: Long,
)
data class SavedRouteRow(
    val id: String,
    val name: String,
    val mode: String,
    val originLabel: String,
    val destLabel: String,
    val createdAtSeconds: Double,
)
data class SavedMarker(
    val id: String,
    val placeId: String,
    val listId: String?,
    val name: String,
    val lat: Double,
    val lng: Double,
    val color: Int,
    val parking: Boolean,
)
data class ParkingRow(val id: String, val lat: Double, val lng: Double, val savedAtSeconds: Double) {
    companion object {
        fun of(p: ParkedSpot) = ParkingRow("${p.savedAtMillis}:${p.lat}:${p.lng}", p.lat, p.lng, p.savedAtMillis / 1000.0)
    }
}

enum class SavedImportKind {
    ADDED, NOTHING_NEW, WRONG_FORMAT, UNREADABLE, BUSY, LIST_ADDED, CANCELLED, FAILED,
    /** "Use Vela without Google" is on: the link path refuses instead of opening a Google page. */
    GOOGLE_DISABLED,
    /** Not a Google host, so there is no list page to read. */
    LINK_INVALID,
    /** The page did not carry a list: consent wall, private list, or a changed page shape. */
    GOOGLE_UNREADABLE,
}

data class SavedImport(
    val kind: SavedImportKind,
    val name: String? = null,
    val count: Int = 0,
    val missed: Int = 0,
    val needGoogle: Int = 0,
    /** How many lists the import wrote: a My Maps file with folders writes one per folder. */
    val lists: Int = 0,
) {
    val kindName: String get() = kind.name
}

/**
 * Saved places, lists, recents, Home and Work, saved routes and parking. This is the iOS facet of
 * Android's saved `MapViewModel` methods over the unchanged common stores. Construction is inert;
 * [start] restores the state. Intents are synchronous except [importFile], whose Takeout lookups
 * run on [scope]. No user-visible formatted strings live here: Swift formats the typed rows.
 */
class SavedStore(
    keyValues: KeyValueStores,
    private val clock: Clock,
    private val scope: CoroutineScope,
    private val source: () -> MapDataSource? = { null },
) {
    private val savedStore = SavedPlaceStore(keyValues)
    private val listStore = PlaceListStore(keyValues)
    private val shortcutStore = PlaceShortcutStore(keyValues)
    private val parkingStore = ParkingStore(keyValues)
    private val routeStore = SavedRouteStore(keyValues)
    private val recentSearchStore = RecentSearchStore(keyValues, clock)
    private val recentPlaceStore = RecentPlaceStore(keyValues, clock)

    private val _state = MutableStateFlow(SavedState())
    val state: StateFlow<SavedState> = _state.asStateFlow()

    private var started = false
    private var myLocation: LatLng? = null
    private var mapCenter: LatLng? = null
    private var importJob: Job? = null
    private var pendingDrafts: List<SavedImportDraft>? = null
    /** Stops a fetch Swift owns (the hidden list page) when the user cancels. */
    private var externalCancel: (() -> Unit)? = null

    fun start() {
        if (started) return
        started = true
        ShortcutKind.entries.forEach { kind ->
            shortcutStore.get(kind)?.labelMended()?.let { shortcutStore.set(kind, it) }
        }
        refresh()
    }

    private fun refresh() {
        val current = parkingStore.current()
        _state.update {
            it.copy(
                saved = savedStore.saved(),
                lists = listStore.lists(),
                home = shortcutStore.get(ShortcutKind.HOME),
                work = shortcutStore.get(ShortcutKind.WORK),
                parking = current?.let { c -> ParkedSpot(c.lat, c.lng, c.savedAtMillis) },
                parkingHistory = parkingStore.history(),
                savedRoutes = routeStore.all(),
                recentSearches = recentSearchStore.recent(),
                recentPlaces = recentPlaceStore.recent(),
            )
        }
    }

    fun watch(onChange: (SavedState) -> Unit): Cancellable {
        val job = scope.launch { state.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    /** Android's `runSearch` records a submitted nonblank query before its network answer. */
    fun recordSearch(query: String) {
        if (!started || query.isBlank()) return
        recentSearchStore.add(query)
        _state.update { it.copy(recentSearches = recentSearchStore.recent()) }
    }

    /** Android's `selectPlace` remembers the lightweight place, without the point mark. */
    fun recordPlace(place: Place) {
        if (!started) return
        recentPlaceStore.add(SavedPlace.of(place))
        _state.update { it.copy(recentPlaces = recentPlaceStore.recent()) }
    }

    fun removeRecentSearch(query: String) {
        recentSearchStore.remove(query)
        _state.update { it.copy(recentSearches = recentSearchStore.recent()) }
    }

    fun removeRecentPlace(placeId: String) {
        recentPlaceStore.remove(placeId)
        _state.update { it.copy(recentPlaces = recentPlaceStore.recent()) }
    }

    fun clearRecents() {
        recentSearchStore.clear()
        recentPlaceStore.clear()
        _state.update { it.copy(recentSearches = emptyList(), recentPlaces = emptyList()) }
    }

    /** Toggle the quick-saved entry, the Saved section in SwiftUI. Returns its new saved state. */
    fun toggleSave(place: Place): Boolean {
        val nowSaved = savedStore.toggle(SavedPlace.of(place).copy(bare = !PlaceStore.isListing(place)))
        _state.update { it.copy(saved = savedStore.saved()) }
        return nowSaved
    }

    fun removeSaved(placeId: String) {
        _state.update { it.copy(saved = savedStore.removeAll(setOf(placeId))) }
    }

    fun contains(placeId: String, featureId: String? = null): Boolean =
        _state.value.saved.any { it.id == placeId } ||
            _state.value.lists.any { list -> list.places.any { it.matches(placeId, featureId) } }

    fun renamePlace(placeId: String, name: String, featureId: String? = null) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        savedStore.rename(placeId, trimmed)
        val lists = listStore.rename(placeId, trimmed, featureId)
        _state.update { it.copy(saved = savedStore.saved(), lists = lists) }
    }

    fun createList(name: String): String {
        val trimmed = validatedListName(name) ?: return ""
        val base = "list:" + trimmed.hashCode().toString(16) + ":" + _state.value.lists.size
        var id = base
        var suffix = 2
        while (_state.value.lists.any { it.id == id }) id = "$base:${suffix++}"
        val lists = listStore.create(PlaceList(id, trimmed))
        _state.update { it.copy(lists = lists) }
        return id
    }

    /** Renames a list. False for a blank or overlong name; the stored lists are untouched. */
    fun renameList(listId: String, name: String): Boolean {
        val trimmed = validatedListName(name) ?: return false
        val list = _state.value.lists.firstOrNull { it.id == listId } ?: return false
        _state.update { it.copy(lists = listStore.update(list.copy(name = trimmed))) }
        return true
    }

    /** The list editor's save: name, icon, color and sound in one write. */
    fun updateList(listId: String, name: String, icon: String, color: Long, alert: String?): Boolean {
        val trimmed = validatedListName(name) ?: return false
        val list = _state.value.lists.firstOrNull { it.id == listId } ?: return false
        _state.update { it.copy(lists = listStore.update(list.copy(name = trimmed, icon = icon, color = color, alert = alert))) }
        return true
    }

    /** A list's drive-by sound, or null for none. */
    fun setListAlert(listId: String, alert: String?) {
        val list = _state.value.lists.firstOrNull { it.id == listId } ?: return
        if (list.alert == alert) return
        _state.update { it.copy(lists = listStore.update(list.copy(alert = alert))) }
    }

    fun deleteList(listId: String) {
        _state.update { it.copy(lists = listStore.delete(listId)) }
    }

    fun moveList(listId: String, delta: Int) {
        _state.update { it.copy(lists = listStore.move(listId, delta)) }
    }

    /** Drag reorder: [orderedIds] must be the same set as the current lists, else nothing moves. */
    fun reorderLists(orderedIds: List<String>) {
        val current = _state.value.lists
        if (orderedIds.size != current.size || orderedIds.toSet() != current.mapTo(HashSet()) { it.id }) return
        var lists = current
        orderedIds.forEachIndexed { target, id ->
            val from = lists.indexOfFirst { it.id == id }
            if (from >= 0 && from != target) {
                lists = listStore.move(id, target - from)
            }
        }
        _state.update { it.copy(lists = lists) }
    }

    fun addToList(listId: String, place: Place) {
        _state.update { it.copy(lists = listStore.addPlace(listId, ListPlace.of(place))) }
    }

    fun removeFromList(listId: String, placeId: String, featureId: String? = null) {
        _state.update { it.copy(lists = listStore.removePlace(listId, placeId, featureId)) }
    }

    fun moveListPlace(fromListId: String, placeId: String, toListId: String) {
        _state.update { it.copy(lists = listStore.movePlaces(fromListId, setOf(placeId), toListId)) }
    }

    /** Bulk remove from one list in a single write. */
    fun removeListPlaces(listId: String, placeIds: List<String>) {
        if (placeIds.isEmpty()) return
        _state.update { it.copy(lists = listStore.removePlaces(listId, placeIds.toSet())) }
    }

    /** Bulk move from one list to another; a missing target leaves every entry where it was. */
    fun moveListPlaces(fromListId: String, placeIds: List<String>, toListId: String) {
        if (placeIds.isEmpty() || fromListId == toListId) return
        _state.update { it.copy(lists = listStore.movePlaces(fromListId, placeIds.toSet(), toListId)) }
    }

    /** Bulk remove of quick saves in a single write. */
    fun removeSavedPlaces(placeIds: List<String>) {
        if (placeIds.isEmpty()) return
        _state.update { it.copy(saved = savedStore.removeAll(placeIds.toSet())) }
    }

    /** Bulk move of quick saves into a list, keeping each place's own icon as Android does. */
    fun moveSavedPlaces(placeIds: List<String>, toListId: String) {
        if (placeIds.isEmpty() || _state.value.lists.none { it.id == toListId }) return
        val wanted = placeIds.toSet()
        val moving = _state.value.saved.filter { it.id in wanted }
        if (moving.isEmpty()) return
        val lists = listStore.addPlaces(
            toListId,
            moving.map { ListPlace.of(it.toPlace()).copy(icon = it.icon) },
        )
        _state.update { it.copy(saved = savedStore.removeAll(wanted), lists = lists) }
    }

    /** Drag reorder inside a list. [orderedIds] must name exactly the entries the list holds. */
    fun reorderListPlaces(listId: String, orderedIds: List<String>) {
        val list = _state.value.lists.firstOrNull { it.id == listId } ?: return
        if (orderedIds.size != list.places.size || orderedIds.toSet() != list.places.mapTo(HashSet()) { it.id }) return
        val byId = list.places.associateBy { it.id }
        val places = orderedIds.mapNotNull { byId[it] }
        _state.update { it.copy(lists = listStore.update(list.copy(places = places))) }
    }

    /** Move a quick-saved place into a list, preserving its icon as Android's bulk action does. */
    fun moveSavedPlace(placeId: String, toListId: String) = moveSavedPlaces(listOf(placeId), toListId)

    fun setNote(placeId: String, note: String?, featureId: String? = null) {
        _state.update { it.copy(lists = listStore.setNote(placeId, note, featureId)) }
    }

    fun setShortcut(kind: ShortcutKind, place: Place) {
        val saved = SavedPlace.of(place).copy(bare = !PlaceStore.isListing(place))
        setShortcut(kind, saved)
    }

    fun setShortcut(kind: ShortcutKind, saved: SavedPlace) {
        shortcutStore.set(kind, saved.copy(address = saved.addressKeepingStreet(), streetKept = saved.streetKept || saved.isPoint))
        refreshShortcuts()
    }

    fun clearShortcut(kind: ShortcutKind) {
        shortcutStore.set(kind, null)
        refreshShortcuts()
    }

    /** Swift's intent without exposing the core enum at the call site. */
    fun setShortcutNamed(name: String, place: Place) {
        ShortcutKind.entries.firstOrNull { it.name == name }?.let { setShortcut(it, place) }
    }

    fun clearShortcutNamed(name: String) {
        ShortcutKind.entries.firstOrNull { it.name == name }?.let(::clearShortcut)
    }

    private fun refreshShortcuts() {
        _state.update {
            it.copy(home = shortcutStore.get(ShortcutKind.HOME), work = shortcutStore.get(ShortcutKind.WORK))
        }
    }

    fun saveParking(place: Place) = saveParking(place.location)

    fun saveParking(at: LatLng) {
        parkingStore.save(ParkedSpot(at.lat, at.lng, clock.nowMillis()))
        refreshParking()
    }

    /** The map's parking button. False until a location fix has arrived. */
    fun saveParkingAtMyLocation(): Boolean {
        val at = myLocation ?: return false
        saveParking(at)
        return true
    }

    fun clearParking() {
        parkingStore.clearCurrent()
        refreshParking()
    }

    fun restoreParking(row: ParkingRow) {
        parkingStore.restore(ParkedSpot(row.lat, row.lng, (row.savedAtSeconds * 1000).toLong()))
        refreshParking()
    }

    fun deleteParking(row: ParkingRow) {
        parkingStore.deleteFromHistory(ParkedSpot(row.lat, row.lng, (row.savedAtSeconds * 1000).toLong()))
        refreshParking()
    }

    fun clearParkingHistory() {
        parkingStore.clearHistory()
        refreshParking()
    }

    private fun refreshParking() {
        val current = parkingStore.current()
        _state.update {
            it.copy(
                parking = current?.let { c -> ParkedSpot(c.lat, c.lng, c.savedAtMillis) },
                parkingHistory = parkingStore.history(),
            )
        }
    }

    fun onLocation(lat: Double, lng: Double) {
        myLocation = LatLng(lat, lng)
    }

    fun onMapCenter(lat: Double, lng: Double) {
        mapCenter = LatLng(lat, lng)
    }

    /** Save the active route's exact guidance line and ends. False when no route line is ready. */
    fun saveActiveRoute(route: RouteState, name: String): Boolean {
        val active = route.active ?: return false
        if (active.polyline.size < 2) return false
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return false
        val now = clock.nowMillis()
        val base = "route:" + now.toString(16)
        var id = base
        var suffix = 2
        while (_state.value.savedRoutes.any { it.id == id }) id = "$base:${suffix++}"
        val saved = SavedRoute(
            id = id,
            name = trimmed,
            originLabel = (if (route.reversed) route.destination?.name else route.origin?.name).orEmpty(),
            mode = route.mode.name,
            originLat = active.polyline.first().lat,
            originLng = active.polyline.first().lng,
            destLat = active.polyline.last().lat,
            destLng = active.polyline.last().lng,
            destLabel = (if (route.reversed) route.origin?.name else route.destination?.name).orEmpty(),
            polyline = PolylineCodec.encode(active.polyline),
            createdAt = now,
        )
        _state.update { it.copy(savedRoutes = routeStore.add(saved)) }
        return true
    }

    fun savedRoute(id: String): SavedRoute? = _state.value.savedRoutes.firstOrNull { it.id == id }

    fun renameRoute(id: String, name: String) {
        _state.update { it.copy(savedRoutes = routeStore.rename(id, name)) }
    }

    fun deleteRoute(id: String) {
        _state.update { it.copy(savedRoutes = routeStore.delete(id)) }
    }

    fun savedPlace(placeId: String): SavedPlace? = _state.value.saved.firstOrNull { it.id == placeId }

    fun listPlace(listId: String, placeId: String): ListPlace? =
        _state.value.lists.firstOrNull { it.id == listId }?.places?.firstOrNull { it.id == placeId }

    fun recentPlace(placeId: String): SavedPlace? = _state.value.recentPlaces.firstOrNull { it.place.id == placeId }?.place

    /** The current parking point as a lightweight place. Swift supplies its localized display name. */
    fun parkingPlace(name: String): Place? = _state.value.parking?.let {
        Place(id = "parking", name = name, location = LatLng(it.lat, it.lng))
    }

    /** Import a Vela JSON backup, GPX, KML, GeoJSON or one Takeout list CSV picked by Swift. */
    fun importFile(text: String, name: String) {
        if (!started) return
        if (importJob?.isCompleted == false || externalCancel != null || _state.value.importing) {
            _state.update { it.copy(lastImport = SavedImport(SavedImportKind.BUSY)) }
            return
        }
        _state.update { it.copy(importing = true, importDone = 0, importTotal = 0, lastImport = null) }
        importJob = scope.launch {
            try {
                val result = import(text, name.substringBeforeLast('.').trim().ifBlank { "Takeout" })
                refresh()
                _state.update { it.copy(importing = false, lastImport = result.toSavedImport()) }
            } catch (e: CancellationException) {
                refresh()
                _state.update { it.copy(importing = false, lastImport = SavedImport(SavedImportKind.CANCELLED)) }
                throw e
            } catch (_: Exception) {
                // The Takeout importer has already rolled its target list back on this path.
                refresh()
                _state.update { it.copy(importing = false, lastImport = SavedImport(SavedImportKind.FAILED)) }
            }
        }
    }

    /** Stops the current import. Takeout keeps the places completed before cancellation. */
    fun cancelImport() {
        val job = importJob
        if (job != null && !job.isCompleted) {
            job.cancel()
            // Also covers cancellation before the launched body gets its first turn on the main thread.
            refresh()
            _state.update { it.copy(importing = false, lastImport = SavedImport(SavedImportKind.CANCELLED)) }
            return
        }
        // A list page or file parse Swift owns: stop it, and let its late answer be ignored.
        if (externalCancel != null || _state.value.importing) {
            externalCancel?.invoke()
            externalCancel = null
            _state.update {
                it.copy(importing = false, importDone = 0, importTotal = 0, lastImport = SavedImport(SavedImportKind.CANCELLED))
            }
        }
    }

    // --- Google shared list and My Maps file (IMP-GOOGLE) ------------------------------------

    /** False with "Use Vela without Google": the list page is not opened at all. */
    fun googleListAvailable(): Boolean = !NoGoogle.enabled

    /** Records the refusal Swift shows when the link path is unavailable. */
    fun noteGoogleListUnavailable() {
        _state.update { it.copy(lastImport = SavedImport(SavedImportKind.GOOGLE_DISABLED)) }
    }

    /**
     * Opens the progress state for a page Swift is about to load. False, with the reason already in
     * [SavedState.lastImport], when Google is off, another import runs or [link] is not a Google
     * host: no request is made and no partial list is staged.
     */
    fun beginGoogleListImport(link: String): Boolean {
        if (!started) return false
        if (_state.value.importing) {
            _state.update { it.copy(lastImport = SavedImport(SavedImportKind.BUSY)) }
            return false
        }
        if (NoGoogle.enabled) {
            noteGoogleListUnavailable()
            return false
        }
        if (!SavedListImport.isGoogleLink(link)) {
            _state.update { it.copy(lastImport = SavedImport(SavedImportKind.LINK_INVALID)) }
            return false
        }
        pendingDrafts = null
        _state.update {
            it.copy(
                importing = true, importDone = 0, importTotal = SavedListImport.GOOGLE_STAGES,
                lastImport = null, pendingImport = null,
            )
        }
        return true
    }

    /** Swift registers the handle that stops its hidden page, or null when it ends. */
    fun setExternalImportCancel(cancel: (() -> Unit)?) {
        externalCancel = cancel
    }

    fun googleListProgress(done: Int) {
        _state.update {
            if (!it.importing) it else it.copy(importDone = done.coerceIn(0, SavedListImport.GOOGLE_STAGES))
        }
    }

    /**
     * Hands the fetched list body to the same parser Android uses. A blank body, a consent wall or
     * a changed reply shape ends in [SavedImportKind.GOOGLE_UNREADABLE]; nothing is invented and no
     * list is written.
     */
    fun finishGoogleListImport(payload: String?, link: String) {
        externalCancel = null
        if (!_state.value.importing) return
        val imported = payload?.takeIf { it.isNotBlank() }?.let { EntityListParser.parse(it) }
        if (imported == null || imported.places.isEmpty()) {
            _state.update {
                it.copy(
                    importing = false, importDone = 0, importTotal = 0,
                    lastImport = SavedImport(SavedImportKind.GOOGLE_UNREADABLE),
                )
            }
            return
        }
        val draft = SavedImportDraft(
            title = imported.title,
            description = imported.description,
            places = imported.places.map { ListPlace.of(it) },
            shapes = imported.shapes,
            sourceId = "list:" + link.trim(),
            color = DEFAULT_LIST_COLOR,
        )
        _state.update { it.copy(importing = false, importDone = SavedListImport.GOOGLE_STAGES) }
        stage(listOf(draft), source = "GOOGLE", title = imported.title)
    }

    /** The hidden page died, or the fetch failed: no list, with the failure left on screen. */
    fun failGoogleListImport() {
        externalCancel = null
        if (!_state.value.importing) return
        _state.update {
            it.copy(
                importing = false, importDone = 0, importTotal = 0,
                lastImport = SavedImport(SavedImportKind.FAILED),
            )
        }
    }

    /**
     * A KML or KMZ file picked by Swift. KMZ is unzipped here; a file that is not My Maps still
     * reads through [PlaceImport] as one flat list. False, with [SavedImportKind.UNREADABLE], when
     * the text carries no place.
     */
    fun importKmlFile(bytes: ByteArray, name: String): Boolean {
        if (!started) return false
        val text = SavedKmz.kml(bytes) ?: runCatching { bytes.decodeToString() }.getOrNull()
        return importKmlText(text, name)
    }

    /** The text form of [importKmlFile], for tests and a file the picker already decoded. */
    fun importKmlText(text: String?, name: String): Boolean {
        if (!started) return false
        if (text.isNullOrBlank()) {
            _state.update { it.copy(lastImport = SavedImport(SavedImportKind.UNREADABLE)) }
            return false
        }
        val base = name.substringBeforeLast('.').trim().ifBlank { "My Maps" }
        val parsed = MyMapKml.lists(text)
        val drafts = if (parsed.isNotEmpty()) {
            parsed.map { list ->
                SavedImportDraft(
                    title = list.title,
                    description = list.description,
                    places = list.places.map { ListPlace.of(it) },
                    shapes = list.shapes,
                    sourceId = "kml:$base|${list.title}",
                    color = list.places.firstNotNullOfOrNull { it.pinColor } ?: DEFAULT_LIST_COLOR,
                )
            }
        } else {
            val flat = PlaceImport.parse(text)
            if (flat.isEmpty()) {
                _state.update { it.copy(lastImport = SavedImport(SavedImportKind.UNREADABLE)) }
                return false
            }
            listOf(
                SavedImportDraft(
                    title = base,
                    description = null,
                    places = flat.map { ListPlace(it.id, it.name, it.lat, it.lng, it.address) },
                    shapes = emptyList(),
                    sourceId = "kml:$base",
                    color = DEFAULT_LIST_COLOR,
                )
            )
        }
        return stage(drafts, source = "FILE", title = base)
    }

    /** Writes the merge or the replace the user chose for a staged import. `MERGE` is the default. */
    fun commitPendingImport(mode: String) {
        val drafts = pendingDrafts ?: return
        val title = _state.value.pendingImport?.title.orEmpty()
        commit(drafts, replace = mode.equals("REPLACE", ignoreCase = true), sourceTitle = title)
    }

    /** Leaves an existing list untouched and drops the staged import. */
    fun cancelPendingImport() {
        pendingDrafts = null
        _state.update { it.copy(pendingImport = null) }
    }

    /**
     * Stages [drafts]. When every target is new the import is written at once, as a first import
     * should be; when one already exists nothing is written until the user answers merge or
     * replace, so a second import can never silently double a list.
     */
    private fun stage(drafts: List<SavedImportDraft>, source: String, title: String): Boolean {
        if (drafts.isEmpty()) return false
        val current = _state.value.lists
        val staged = drafts.map { draft ->
            val (existing, listId) = importTarget(current, draft.title, draft.sourceId)
            draft.copy(listId = listId, existingId = existing?.id)
        }
        if (staged.none { it.existingId != null }) {
            commit(staged, replace = false, sourceTitle = title)
            return true
        }
        pendingDrafts = staged
        val rows = staged.map { draft ->
            SavedPendingList(
                title = draft.title,
                count = draft.places.size,
                existingListId = draft.existingId,
                existingCount = current.firstOrNull { it.id == draft.existingId }?.places?.size ?: 0,
            )
        }
        _state.update {
            it.copy(
                importing = false, importDone = 0, importTotal = 0,
                pendingImport = SavedPendingImport(source, title, staged.sumOf { draft -> draft.places.size }, rows),
            )
        }
        return true
    }

    private fun commit(drafts: List<SavedImportDraft>, replace: Boolean, sourceTitle: String) {
        var added = 0
        val created = ArrayList<SavedImportDraft>()
        for (draft in drafts) {
            val lists = listStore.lists()
            val existing = draft.existingId?.let { id -> lists.firstOrNull { it.id == id } }
            when {
                existing == null -> {
                    created += draft
                    added += draft.places.size
                }
                replace -> {
                    listStore.update(
                        existing.copy(
                            places = draft.places, shapes = draft.shapes,
                            description = draft.description ?: existing.description,
                        )
                    )
                    added += draft.places.size
                }
                else -> {
                    val fresh = draft.places.filter { place -> existing.places.none { it.matches(place.id, place.featureId) } }
                    val shapes = draft.shapes.filter { shape -> existing.shapes.none { it == shape } }
                    listStore.update(existing.copy(places = existing.places + fresh, shapes = existing.shapes + shapes))
                    added += fresh.size
                }
            }
        }
        // Store.create() puts a new list first: create in reverse so the file's folder order is the
        // order the user sees in Your lists.
        for (draft in created.asReversed()) {
            listStore.create(
                PlaceList(
                    id = draft.listId, name = draft.title, color = draft.color,
                    description = draft.description, places = draft.places, shapes = draft.shapes,
                )
            )
        }
        pendingDrafts = null
        refresh()
        _state.update {
            val unchanged = added == 0 && drafts.all { draft -> draft.existingId != null }
            it.copy(
                importing = false, importDone = 0, importTotal = 0, pendingImport = null,
                lastImport = if (unchanged) SavedImport(SavedImportKind.NOTHING_NEW)
                else SavedImport(SavedImportKind.LIST_ADDED, sourceTitle, added, 0, 0, drafts.size),
            )
        }
    }

    /** The same portable one-list JSON that Android shares and imports back. */
    fun exportListJson(listId: String): String? = listStore.exportJson(listId)

    /** Quick saves in [format] ([SavedExportFormat] name), or null with nothing saved. */
    fun exportSaved(format: String): String? {
        val places = _state.value.saved
        if (places.isEmpty()) return null
        val chosen = formatOf(format)
        if (chosen == SavedExportFormat.JSON) return savedStore.exportJson()
        return SavedExport.places(places, "Vela saved places", chosen)
    }

    /** Saved places only, in the JSON file Android writes. */
    fun exportSavedJson(): String? = exportSaved(SavedExportFormat.JSON.name)

    /** Every list in the JSON file Android writes, or null with no list. */
    fun exportListsJson(): String? {
        val lists = _state.value.lists
        if (lists.isEmpty()) return null
        return listStore.exportJson()
    }

    /** One list in [format], or null when it does not exist. JSON keeps every field and the
     *  membership; GPX and KML keep only its places' names, coordinates and addresses. */
    fun exportList(listId: String, format: String): String? {
        val list = _state.value.lists.firstOrNull { it.id == listId } ?: return null
        val chosen = formatOf(format)
        if (chosen == SavedExportFormat.JSON) return listStore.exportJson(listId)
        return SavedExport.places(list.places.map(SavedExport::place), list.name, chosen)
    }

    /** One place in [format]: a quick save when [listId] is null, else that list's entry. */
    fun exportPlace(listId: String?, placeId: String, format: String): String? {
        val place = if (listId == null) {
            _state.value.saved.firstOrNull { it.id == placeId }
        } else {
            _state.value.lists.firstOrNull { it.id == listId }
                ?.places?.firstOrNull { it.id == placeId }?.let(SavedExport::place)
        } ?: return null
        return SavedExport.places(listOf(place), place.name, formatOf(format))
    }

    private fun formatOf(name: String): SavedExportFormat =
        SavedExportFormat.entries.firstOrNull { it.name.equals(name, ignoreCase = true) }
            ?: SavedExportFormat.JSON

    private suspend fun import(text: String, name: String): ImportResult {
        if (TakeoutCsv.isTakeoutCsv(text)) return importTakeout(text, name)
        // SavedPlace requires coordinates, so its decoder rejects a PlaceList export. The reverse
        // is not true: a list would accept a saved place as an empty list under ignoreUnknownKeys.
        val saved = savedStore.importMerge(text)
        if (saved !is ImportResult.WrongFormat) return saved
        return listStore.importMerge(text)
    }

    /** Port of Android's Takeout importer: pin rows are local, listing rows use their feature id. */
    private suspend fun importTakeout(text: String, name: String): ImportResult {
        val rows = TakeoutCsv.parse(text)
        if (rows.isEmpty()) return ImportResult.ListAdded(name, 0, 0, 0)
        val near = myLocation ?: mapCenter
        val places = ArrayList<ListPlace>()
        var missed = 0
        var needGoogle = 0
        var lookups = 0
        val (existing, listId) = importTarget(listStore.lists(), name, "takeout:$name")
        val previous = existing?.places.orEmpty()
        val existingBefore = existing?.copy(places = previous)
        val known = TakeoutCsv.keyed(previous)
        _state.update { it.copy(importDone = 0, importTotal = rows.size) }

        fun save(all: List<ListPlace>) {
            val current = listStore.lists().firstOrNull { it.id == listId }
            val list = current?.copy(places = all) ?: PlaceList(id = listId, name = name, places = all)
            val lists = if (current != null) listStore.update(list) else listStore.create(list)
            _state.update { it.copy(lists = lists) }
        }

        suspend fun lookup(title: String, bias: LatLng?): List<Place> = try {
            source()?.search(title, near = bias)?.places.orEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            emptyList()
        }

        var nextSave = TAKEOUT_SAVE_EVERY
        try {
            for ((index, row) in rows.withIndex()) {
                val link = TakeoutCsv.readLink(row.url)
                val title = row.title.ifBlank { link?.name.orEmpty() }
                val note = listOfNotNull(row.note, row.comment).joinToString("\n").ifBlank { null }
                val lat = link?.lat
                val lng = link?.lng
                val reuse = link?.featureKey?.let { known[it] }
                when {
                    link != null && lat != null && lng != null -> places += ListPlace(
                        id = "imp:" + Fmt.fixed(lat, 5) + "," + Fmt.fixed(lng, 5),
                        name = title.ifBlank { Fmt.fixed(lat, 4) + ", " + Fmt.fixed(lng, 4) }.take(120),
                        lat = lat,
                        lng = lng,
                        note = note,
                        featureId = link.featureId,
                    )
                    reuse != null -> places += reuse.copy(note = note)
                    title.isBlank() -> missed++
                    NoGoogle.enabled || source() == null -> needGoogle++
                    else -> {
                        val key = link?.featureKey
                        if (lookups++ > 0) delay(TAKEOUT_LOOKUP_GAP_MS)
                        val hits = lookup(title, link?.cellCenter() ?: near)
                        val wide = if (key != null && TakeoutCsv.byKey(hits, key) == null) {
                            lookups++
                            delay(TAKEOUT_LOOKUP_GAP_MS)
                            lookup(title, null)
                        } else emptyList()
                        val hit = TakeoutCsv.pick(hits, wide, key, title)
                        if (hit != null) places += ListPlace.of(hit).copy(note = note) else missed++
                    }
                }
                if (lookups >= nextSave && places.isNotEmpty()) {
                    save(TakeoutCsv.partial(places, previous))
                    nextSave = lookups + TAKEOUT_SAVE_EVERY
                }
                _state.update { it.copy(importDone = index + 1, importTotal = rows.size) }
            }
        } catch (e: CancellationException) {
            // Cancelling keeps what is done, as Android does.
            if (places.isNotEmpty() || existing != null) save(TakeoutCsv.partial(places, previous))
            throw e
        } catch (e: Exception) {
            // A run that fails (rather than being canceled) leaves the library exactly as it
            // found it: a new list is removed, an existing one gets its old entries back.
            if (existingBefore != null) listStore.update(existingBefore) else listStore.delete(listId)
            _state.update { it.copy(lists = listStore.lists()) }
            throw e
        }
        // A completed rerun replaces the old list even when every lookup failed. Keeping the old
        // rows here would resurrect places that the finished import had determined were stale.
        if (places.isNotEmpty() || existing != null) save(places)
        return ImportResult.ListAdded(name, places.size, missed, needGoogle)
    }

    companion object {
        const val TAKEOUT_LOOKUP_GAP_MS = 400L
        const val TAKEOUT_SAVE_EVERY = 25
        /** The list editor's name limit, as Android's bulk new-list dialog caps its field. */
        const val MAX_LIST_NAME = 40

        /** The trimmed name, or null when it is blank or longer than [MAX_LIST_NAME]. */
        fun validatedListName(name: String): String? {
            val trimmed = name.trim()
            return trimmed.takeIf { it.isNotEmpty() && it.length <= MAX_LIST_NAME }
        }

        /** Canonical Google link: the exact listing by unsigned cid, else a name and point query. */
        fun sharePlaceUrl(place: Place): String {
            val cid = place.featureId?.substringAfter(':', "")?.removePrefix("0x")?.takeIf { it.isNotBlank() }
                ?.let { hex -> runCatching { hex.toULong(16).toString() }.getOrNull() }
            if (cid != null) return "https://www.google.com/maps?cid=$cid"
            val name = UrlCodec.encode(place.name).replace("+", "%20")
            return "https://www.google.com/maps/search/?api=1&query=$name%20${place.location.lat}%2C${place.location.lng}"
        }

        private fun ImportResult.toSavedImport(): SavedImport = when (val r = this) {
            is ImportResult.Added -> SavedImport(SavedImportKind.ADDED, count = r.count)
            ImportResult.NothingNew -> SavedImport(SavedImportKind.NOTHING_NEW)
            is ImportResult.WrongFormat -> SavedImport(SavedImportKind.WRONG_FORMAT, name = r.format)
            ImportResult.Unreadable -> SavedImport(SavedImportKind.UNREADABLE)
            ImportResult.Busy -> SavedImport(SavedImportKind.BUSY)
            is ImportResult.ListAdded -> SavedImport(SavedImportKind.LIST_ADDED, r.name, r.added, r.missed, r.needGoogle)
        }
    }
}

/**
 * The list sound choices shown by the SwiftUI editor, and the tone data Swift synthesizes. The
 * frequencies and durations stay in [PassAlerts] so iOS and Android choose from one table; this
 * object only exposes one typed note per row for the AVFoundation call.
 */
object SavedListSounds {
    /** Values stored in [PlaceList.alert]; null is the off choice and is not listed here. */
    val KEYS = PassAlerts.SOUNDS

    /** True for the "say its name" choice, which the Swift voice speaks instead of a tone. */
    fun isName(sound: String): Boolean = sound == PassAlerts.NAME

    /** A tone as typed notes; null for "say its name" or an unknown key. */
    fun notes(sound: String): List<SavedToneNote>? = PassAlerts.notes(sound)?.map {
        SavedToneNote(it.first, it.second.toDouble())
    }
}

data class SavedToneNote(val hz: Double, val milliseconds: Double)
