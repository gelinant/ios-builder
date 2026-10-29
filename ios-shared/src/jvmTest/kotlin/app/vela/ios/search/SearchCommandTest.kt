package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SearchCommandTest {
    @Test
    fun typedCommandsMatchTheAndroidVocabulary() {
        assertEquals("home", SearchCommands.parse("home", "en")?.kind)
        assertEquals("work", SearchCommands.parse("take me to work", "en")?.kind)
        assertEquals("directions", SearchCommands.parse("directions to coffee", "en")?.kind)
        assertEquals("coffee", SearchCommands.parse("directions to coffee", "en")?.query)
        assertEquals("search", SearchCommands.parse("coffee near me", "en")?.kind)
        assertEquals("coffee", SearchCommands.parse("coffee near me", "en")?.query)
    }

    @Test
    fun alongRouteKeepsTheQueryAndNeverFallsBackToAKeywordSearch() {
        assertEquals("along", SearchCommands.parse("search along the route for coffee", "en")?.kind)
        assertEquals("coffee", SearchCommands.parse("search along the route for coffee", "en")?.query)
        assertEquals("coffee", SearchCommands.parse("search along the route coffee", "en")?.query)
        assertEquals("coffee", SearchCommands.parse("coffee along the route", "en")?.query)
        assertEquals("gas", SearchCommands.parse("search for gas along the route", "en")?.query)
        assertEquals("", SearchCommands.parse("search along the route", "en")?.query)
    }

    @Test
    fun callResolvesThePersonNotTheWords() {
        assertEquals("call", SearchCommands.parse("call Ada Lovelace", "en")?.kind)
        assertEquals("Ada Lovelace", SearchCommands.parse("call Ada Lovelace", "en")?.query)
        assertEquals("call", SearchCommands.parse("dial mom", "en")?.kind)
        assertEquals("Ada Lovelace", SearchCommands.parse("appelle Ada Lovelace", "fr")?.query)
    }

    @Test
    fun plainQueriesStayPlain() {
        assertNull(SearchCommands.parse("Home Depot", "en"))
        assertNull(SearchCommands.parse("coffee", "en"))
    }
}

class SearchCommandCorridorTest {
    // A straight north-south line of about 3.3 km. The middle place is 100 m off the line, the
    // far place 200 m off, and the side place 5 km away, outside the 3 km corridor.
    private val route = listOf(LatLng(37.750, -122.400), LatLng(37.780, -122.400))
    private val nearStart = Place(
        id = "start", name = "start", location = LatLng(37.751, -122.4001))
    private val middle = Place(
        id = "middle", name = "middle", location = LatLng(37.770, -122.4012))
    private val far = Place(
        id = "far", name = "far", location = LatLng(37.779, -122.4022))
    private val outside = Place(
        id = "outside", name = "outside", location = LatLng(37.770, -122.460))

    @Test
    fun keepsTheCorridorAndOrdersByDetour() {
        val result = SearchCommandCorridor.select(
            listOf(far, nearStart, outside, middle), route, maxMeters = 3000.0)
        assertEquals(3, result.found)
        assertEquals(4, result.total)
        assertEquals(3000.0, result.corridorMeters)
        assertEquals(listOf("start", "middle", "far"), result.places.map { it.id })
        // The detour is twice the off-line distance, so the closest row reads first even when it
        // sits earlier along the route.
        assertEquals(18.0, result.places[0].distanceMeters!!, 5.0)
        assertEquals(211.0, result.places[1].distanceMeters!!, 15.0)
    }

    @Test
    fun travelProgressCutsTheTravelledPart() {
        // About 1.65 km along a 3.3 km line: the start-side place is behind the car, the middle
        // place is 100 m off just ahead, and the far place is still near the end.
        val result = SearchCommandCorridor.select(
            listOf(far, nearStart, outside, middle), route, maxMeters = 3000.0,
            traveledMeters = 1650.0)
        assertTrue(result.fromProgress)
        assertEquals(listOf("middle", "far"), result.places.map { it.id })
        // The corridor ran on the remaining half, not on the whole line.
        assertEquals(1690.0, result.routeMeters, 30.0)
        // The detour is still twice the off-line distance, now numbered from the car.
        assertEquals(211.0, result.places[0].distanceMeters!!, 15.0)
    }

    @Test
    fun noProgressKeepsTheWholeRoute() {
        val result = SearchCommandCorridor.select(
            listOf(far, nearStart, outside, middle), route, maxMeters = 3000.0,
            traveledMeters = 0.0)
        assertFalse(result.fromProgress)
        assertEquals(listOf("start", "middle", "far"), result.places.map { it.id })
        assertEquals(3339.0, result.routeMeters, 30.0)
    }

    @Test
    fun noRouteReturnsEverythingUnchanged() {
        val result = SearchCommandCorridor.select(listOf(far, middle), emptyList())
        assertEquals(listOf("far", "middle"), result.places.map { it.id })
        assertEquals(2, result.found)
    }
}
