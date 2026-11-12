package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.ios.privacy.GoogleUses
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
        assertEquals("fallback", store.state.value.match)
    }

    @Test fun aDifferentBusinessOnTheSameSpotIsNeverAdoptedByKind() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(id = "wrong-kind", name = "Neighbor", location = at, category = "Restaurant"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Unnamed cafe", at.lat, at.lng, "cafe")
        runCurrent()
        assertTrue(opened.isEmpty())
        assertEquals("Unnamed cafe", store.state.value.selected?.name)
        assertEquals("fallback", store.state.value.match)
    }

    @Test fun aFarReplyWithTheSameNameFallsBack() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(
                id = "same-name-far", name = "Ferry Building",
                location = LatLng(at.lat + 0.02, at.lng), category = "Marketplace"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, "marketplace")
        runCurrent()
        assertTrue(opened.isEmpty())
        assertEquals("fallback", store.state.value.match)
        assertEquals("Ferry Building", store.state.value.selected?.name)
    }

    @Test fun anAccentedReplyIsTheSameNameAndReportsExact() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(id = "cafe", name = "Café de la Gare", location = LatLng(at.lat + 0.0002, at.lng), category = "Coffee shop"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Cafe de la Gare", at.lat, at.lng, "cafe")
        runCurrent()
        assertEquals(listOf("cafe"), opened.map { it.id })
        assertEquals("exact", store.state.value.match)
        assertNull(store.state.value.selected)
    }

    @Test fun aNameThatOnlyAgreesReportsNear() = runTest {
        val source = PoiSource()
        source.answers = listOf(
            Place(id = "market", name = "Carrefour Market", location = at, category = "Supermarket"),
        )
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Carrefour", at.lat, at.lng, "supermarket")
        runCurrent()
        assertEquals(listOf("market"), opened.map { it.id })
        assertEquals("near", store.state.value.match)
    }

    @Test fun theFallbackCarriesTheDistanceFromTheUser() = runTest {
        val source = PoiSource()
        val store = MapPoiStore({ source }, backgroundScope) { }.apply { start() }
        val me = LatLng(at.lat - 0.001, at.lng)
        store.tap("Ferry Building", at.lat, at.lng, "marketplace", from = me)
        runCurrent()
        val meters = store.state.value.selected?.distanceMeters
        assertTrue(meters != null && meters > 100 && meters < 120)
    }

    @Test fun searchGoogleRunsTheNameAndPointOnlyWhenItAgrees() = runTest {
        val source = PoiSource()
        val store = MapPoiStore({ source }, backgroundScope) { error("a stranger must not open") }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, "marketplace")
        runCurrent()
        assertEquals("fallback", store.state.value.match)
        source.answers = listOf(Place(id = "stranger", name = "Unrelated neighbor", location = at))
        store.searchGoogle()
        runCurrent()
        assertEquals(listOf("Ferry Building", "Ferry Building"), source.queries)
        assertEquals("fallback", store.state.value.match)
        assertTrue(store.state.value.googleSearchFoundNothing)
        assertFalse(store.state.value.resolving)
    }

    @Test fun searchGoogleOpensAnAgreeingListing() = runTest {
        val source = PoiSource()
        val opened = mutableListOf<Place>()
        val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, "marketplace")
        runCurrent()
        source.answers = listOf(Place(id = "listing", name = "Ferry Building", location = at))
        store.searchGoogle()
        runCurrent()
        assertEquals(listOf("listing"), opened.map { it.id })
        assertEquals("exact", store.state.value.match)
    }

    @Test fun normalisationFoldsAccentsAndCase() {
        assertEquals("cafe de la gare", MapPoiStore.normalized("Café de la Gare"))
        assertEquals("mcdonalds", MapPoiStore.normalized("McDonald's"))
        assertEquals("zurich hb", MapPoiStore.normalized("Zürich HB"))
        assertEquals("carrefour", MapPoiStore.normalized("  Carrefour!  "))
        assertTrue(MapPoiStore.nameAgrees("Café de la Gare", "CAFE DE LA GARE"))
        assertTrue(MapPoiStore.nameAgrees("Carrefour", "Carrefour Market"))
        assertFalse(MapPoiStore.nameAgrees("Carrefour", "Boulangerie"))
    }

    @Test fun theDistanceCapsHoldForBusinessesAndSettlements() {
        val near = LatLng(at.lat + 0.005, at.lng) // about 556 m
        val tooFar = LatLng(at.lat + 0.02, at.lng) // about 2.2 km
        val atBusiness = Place(id = "b", name = "Ferry Building", location = near)
        assertEquals(
            "exact",
            MapPoiStore.bestMatch("Ferry Building", at, "marketplace", listOf(atBusiness))?.label ?: "fallback")
        assertNull(MapPoiStore.bestMatch(
            "Ferry Building", at, "marketplace",
            listOf(atBusiness.copy(location = tooFar))))
        // A settlement label answers from much farther, still only on an agreeing name.
        assertEquals(
            "exact",
            MapPoiStore.bestMatch(
                "Davis", at, "city",
                listOf(Place(id = "d", name = "Davis", location = LatLng(at.lat + 0.2, at.lng))))?.label)
        assertNull(MapPoiStore.bestMatch(
            "Davis", at, "city",
            listOf(Place(id = "w", name = "Woodland", location = LatLng(at.lat + 0.2, at.lng)))))
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

    @Test fun lookupOffKeepsTheVelaRowAndAsksNothing() = runTest {
        val source = PoiSource()
        source.answers = listOf(Place(id = "right", name = "Ferry Building", location = at))
        GoogleUses.apply(lookupTappedPlaces = false, resolveShortLinks = true)
        try {
            val opened = mutableListOf<Place>()
            val store = MapPoiStore({ source }, backgroundScope) { opened += it }.apply { start() }
            store.tap("Ferry Building", at.lat, at.lng, null)
            runCurrent()
            assertTrue(source.queries.isEmpty())
            assertTrue(opened.isEmpty())
            assertEquals("Ferry Building", store.state.value.selected?.name)
            assertTrue(store.state.value.googleUnavailable)
        } finally {
            GoogleUses.reset()
        }
    }

    @Test fun closeCancelsThePendingSelection() = runTest {
        val source = PoiSource()
        val store = MapPoiStore({ source }, backgroundScope) { error("closed") }.apply { start() }
        store.tap("Ferry Building", at.lat, at.lng, null)
        store.close()
        assertNull(store.state.value.selected)
    }
}
