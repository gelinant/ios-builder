package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class PoiSource : MapDataSource {
    var answers: List<Place> = emptyList()
    var geocoded: Place? = null
    val queries = mutableListOf<String>()
    var reverseCalls = 0

    override suspend fun searchOnce(query: String, near: LatLng, lang: String?): List<Place> {
        queries += query
        return answers
    }

    override suspend fun reverseGeocode(location: LatLng): Place? {
        reverseCalls++
        return geocoded
    }

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult =
        SearchResult(query, emptyList())

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = error("unused")
}

@OptIn(ExperimentalCoroutinesApi::class)
class MapPoiStoreTest {
    private val at = LatLng(37.7955, -122.3937)

    @Test fun nameAgreementBeatsANearerNeighborWithOneFocusedSearch() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(id = "wrong", name = "Neighbor", location = LatLng(37.79551, -122.39371), category = "Coffee shop"),
            Place(id = "right", name = "Ferry Building Marketplace", location = LatLng(37.7957, -122.3938), category = "Marketplace"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, "marketplace")
        runCurrent()
        assertEquals(listOf("Ferry Building"), source.queries)
        assertEquals(listOf("right"), opened.map { it.id })
        assertNull(store.state.value.selected)
    }

    @Test fun aBadMatchKeepsTheOsmLabelAndMarksGoogleUnavailable() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(id = "wrong", name = "Unrelated neighbor", location = at, category = "Restaurant"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, "marketplace")
        runCurrent()
        assertTrue(opened.isEmpty())
        assertEquals("Ferry Building", store.state.value.selected?.name)
        assertEquals(at, store.state.value.selected?.location)
        assertTrue(store.state.value.googleUnavailable)
        assertFalse(store.state.value.resolving)
    }

    @Test fun noNameMatchNeedsTheSameKindOnTheSameSpot() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(id = "wrong-kind", name = "Neighbor", location = at, category = "Restaurant"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Unnamed cafe", at.lat, at.lng, "cafe")
        runCurrent()
        assertTrue(opened.isEmpty())
        source.answers = listOf(Place(id = "coffee", name = "Neighbor", location = at, category = "Coffee shop"))
        store.tap("Unnamed cafe", at.lat, at.lng, "cafe")
        runCurrent()
        assertEquals(listOf("coffee"), opened.map { it.id })
    }

    @Test fun longPressDropsThenReverseGeocodesTheSamePin() = runTest {
        val source = PoiSource()
        source.geocoded = Place(id = "geo", name = "1 Market Street", location = LatLng(0.0, 0.0), address = "San Francisco")
        val store = MapPoiStore({ source }, backgroundScope) { error("a pin does not open a Google listing") }.apply { start() }
        store.longPress(at.lat, at.lng)
        assertEquals("Dropped pin", store.state.value.selected?.name)
        assertTrue(store.state.value.droppedPin)
        runCurrent()
        assertEquals(1, source.reverseCalls)
        assertTrue(source.queries.isEmpty())
        assertEquals("1 Market Street", store.state.value.selected?.name)
        assertEquals(at, store.state.value.selected?.location)
        assertFalse(store.state.value.resolving)
        assertTrue(store.state.value.droppedPin)
    }

    @Test fun closeCancelsThePendingSelection() = runTest {
        val source = PoiSource()
        val store = MapPoiStore({ source }, backgroundScope) { error("closed") }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, null)
        store.close()
        assertNull(store.state.value.selected)
    }
}
