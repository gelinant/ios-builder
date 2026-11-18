package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary
import app.vela.core.platform.Cancellable
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.NormalForm
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransitAlternativesTest {
    private val base = TransitPreview.sf
    private val rideIndex = base.steps.indexOfFirst { it.line != null }
    private val segments = TransitTrip.segmentsOf(base)
    private val ride = segments.first { it.kind == TransitTrip.KIND_RIDE }

    private val planReply = """
      {"itineraries":[{"startTime":"2026-10-27T16:27:00Z","endTime":"2026-10-27T16:39:00Z","duration":720,
       "legs":[{"mode":"TRAM","startTime":"2026-10-27T16:28:00Z","endTime":"2026-10-27T16:35:00Z","duration":420,
        "routeShortName":"K","headsign":"Embarcadero Station","realTime":false,
        "from":{"name":"Metro Van Ness Station","stopId":"van-ness","lat":37.775127,"lon":-122.41925,
          "departure":"2026-10-27T16:28:00Z","scheduledDeparture":"2026-10-27T16:28:00Z","tz":"America/Los_Angeles"},
        "to":{"name":"Metro Embarcadero Station","stopId":"embarcadero","lat":37.793133,"lon":-122.39643,
          "arrival":"2026-10-27T16:35:00Z","scheduledArrival":"2026-10-27T16:35:00Z","tz":"America/Los_Angeles"},
        "intermediateStops":[{"name":"Metro Civic Center Station/Downtn","stopId":"civic","lat":37.779713,
          "lon":-122.413345,"arrival":"2026-10-27T16:31:00Z","scheduledArrival":"2026-10-27T16:31:00Z",
          "tz":"America/Los_Angeles"}]}]}]}
    """.trimIndent()

    private class FakeHttp(private val reply: (String) -> Pair<Int, String>) : VelaHttp {
        val urls = mutableListOf<String>()
        override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
            urls += request.url
            val (code, body) = reply(request.url)
            callback(HttpResponse(code, emptyList(), body.encodeToByteArray(), request.url), null)
            return Cancellable { }
        }
    }

    private val locale = object : PlatformLocale {
        override fun defaultTag() = "en-US"
        override fun defaultLanguage() = "en"
        override fun preferredTags() = listOf("en-US")
        override fun systemTags() = listOf("en-US")
    }
    private val text = object : TextNormalizer {
        override fun normalize(text: String, form: NormalForm) = text
    }

    @Test fun candidatesAreTheIntermediateStopsOfTheRide() {
        val withIds = base.copy(steps = base.steps.mapIndexed { i, step ->
            if (i == rideIndex) step.copy(intermediateStops = step.intermediateStops.mapIndexed { k, stop ->
                stop.copy(stopId = "stop-$k")
            }) else step
        })
        val candidates = TransitAlternatives.candidates(withIds, ride)
        assertEquals(3, candidates.size)
        assertEquals("Metro Civic Center Station/Downtn", candidates[0].name)
        assertEquals("stop-0", candidates[0].stopId)
        assertEquals(rideIndex, candidates[0].stepIndex)
        // A walk has no intermediate stop to go through.
        assertEquals(emptyList(), TransitAlternatives.candidates(base, segments.first { it.kind == TransitTrip.KIND_WALK }))
    }

    @Test fun theQueryKeepsTheTripsEndsAndDeparture() {
        val candidate = TransitAlternatives.candidates(base, ride).first()
        val query = TransitAlternatives.query(base, ride, candidate)!!
        assertEquals(LatLng(37.7749, -122.4194), query.origin)
        assertEquals(LatLng(37.7942, -122.3946), query.destination)
        assertEquals(TransitTrip.SHIFT_DEPART_AT, query.timeMode)
        assertEquals(base.departureEpochSec, query.timeEpochSec)
        assertEquals(candidate.name, query.viaName)
        assertNull(query.viaStopId, "the recorded trip carried no stop id for an intermediate")
    }

    @Test fun optionsComeFromThePlannersAnswerOnly() {
        val candidate = TransitAlternatives.candidates(base, ride).first()
        val query = TransitAlternatives.query(base, ride, candidate)!!
        val empty = TransitAlternatives.options(query, "civic", emptyList())
        assertTrue(empty.options.isEmpty(), "an empty answer adds no row")
        val one = TransitAlternatives.options(query, "civic", listOf(base))
        assertEquals(1, one.options.size)
        assertEquals("Via ${candidate.name}", one.query)
        assertTrue(!one.viaStopId.isBlank())
    }

    @Test fun aShiftedDepartureReusesTheTripScreensOwnQuery() {
        val header = TransitTripHeader(
            stopName = ride.boardName, lineLabel = ride.lineLabel, direction = ride.direction,
            departures = listOf(
                TransitTripDeparture(
                    clockText = ride.shownDeparture, epochSec = base.departureEpochSec!!,
                    realtime = false, minutes = 1, tripId = null,
                ),
            ),
            available = true,
        )
        val shift = TransitAlternatives.shift(base, ride, header, TransitTrip.SHIFT_DEPART_AT, 15)
        assertNotNull(shift)
        assertEquals(TransitTrip.SHIFT_DEPART_AT, shift.timeMode)
        assertTrue(shift.epochSec > base.departureEpochSec!!)
        assertTrue(TransitTrip.options(listOf(base)).isNotEmpty())
    }

    @Test fun selectionFindsTheSameOptionInTheStoresList() {
        assertEquals(0, TransitAlternatives.selectIndexFor(listOf(base), base.copy()))
        assertEquals(-1, TransitAlternatives.selectIndexFor(listOf(base), base.copy(arrivalEpochSec = 1L)))
        assertEquals(-1, TransitAlternatives.selectIndexFor(emptyList(), base))
    }

    @Test fun aViaSearchSendsTheStopIdAndNeverAPosition() = runTest {
        val http = FakeHttp { 200 to planReply }
        val transit = TransitousHttp(http, locale, text)
        val candidate = TransitAlternatives.candidates(base, ride).first().copy(stopId = "civic")
        val options = TransitAlternatives.plan(transit, base, ride, candidate)
        assertNotNull(options)
        assertEquals(1, options.options.size)
        assertEquals("civic", options.viaStopId)
        assertEquals(1, http.urls.size, "the id in the trip is used; no name lookup")
        assertTrue(http.urls[0].contains("&via=civic"), http.urls[0])
        assertTrue(http.urls[0].contains("/api/v1/plan"))
    }

    @Test fun aStopWithNoIdIsResolvedByNameBeforeThePlan() = runTest {
        val http = FakeHttp { url ->
            if (url.contains("map/stops")) 200 to "[]" else 200 to planReply
        }
        val transit = TransitousHttp(http, locale, text)
        val candidate = TransitAlternatives.candidates(base, ride).first()
        assertNull(TransitAlternatives.plan(transit, base, ride, candidate))
        assertEquals(1, http.urls.size, "no plan is sent when the name matches no stop")
        assertTrue(http.urls[0].contains("map/stops"))
    }

    @Test fun aTripWithNoEndsHasNoViaQuery() {
        val thin: TransitItinerary = base.copy(steps = base.steps.filter { it.line != null }.map {
            it.copy(boardStop = it.boardStop?.copy(location = null), alightStop = it.alightStop?.copy(location = null))
        })
        val segment = TransitTrip.segmentsOf(thin).firstOrNull { it.kind == TransitTrip.KIND_RIDE }!!
        val candidate = TransitAlternatives.candidates(thin, segment).firstOrNull()!!
        assertNull(TransitAlternatives.query(thin, segment, candidate))
    }
}
