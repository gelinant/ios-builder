package app.vela.ios.nav

import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.VelaHttp
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FreeDriveRoadsTest {
    private val at = LocalDateTime(2026, 10, 28, 12, 0)
    private val lat = 37.7749
    private val lng = -122.4194

    @Test fun nearestDrivableWayCarriesItsNameRefAndMphLimit() {
        val body = reply(
            way("footway", 0.00002, name = "Sidewalk", maxspeed = "5"),
            way("primary", 0.00010, name = "Market Street", ref = "US 101", maxspeed = "30 mph"),
        ).encodeToByteArray()
        val road = assertNotNull(FreeDriveRoads.parse(body, lat, lng, at))
        assertEquals("Market Street", road.name)
        assertEquals("US 101", road.ref)
        assertEquals(30 * 1.609344, assertNotNull(road.limitKmh), 1e-6)
        assertEquals("primary", road.highway)
    }

    @Test fun anUntaggedRoadKeepsItsNameAndShowsNoLimit() {
        val body = reply(way("residential", 0.00008, name = "Quiet Street")).encodeToByteArray()
        val road = assertNotNull(FreeDriveRoads.parse(body, lat, lng, at))
        assertEquals("Quiet Street", road.name)
        assertNull(road.ref)
        assertNull(road.limitKmh, "a missing maxspeed must stay blank, never a guessed limit")
    }

    @Test fun aWayOutsideTheSnapIsNotTheRoadUnderTheCar() {
        // 0.001 degrees of latitude is about 111 m, far past the 20 m snap.
        val body = reply(way("primary", 0.001, name = "Next Street", maxspeed = "50")).encodeToByteArray()
        assertNull(FreeDriveRoads.parse(body, lat, lng, at))
    }

    @Test fun aNonDrivableWayNeverAnswers() {
        val body = reply(
            way("cycleway", 0.0, name = "Cycle Path", maxspeed = "20"),
            way("path", 0.0, name = "Footpath"),
        ).encodeToByteArray()
        assertNull(FreeDriveRoads.parse(body, lat, lng, at))
    }

    @Test fun aWayWithNoGeometryIsIgnored() {
        val body = """{"elements":[{"tags":{"highway":"primary","name":"No geometry","maxspeed":"50"}}]}"""
        assertNull(FreeDriveRoads.parse(body.encodeToByteArray(), lat, lng, at))
    }

    @Test fun aBrokenReplyIsNullRatherThanAFabricatedRoad() {
        assertNull(FreeDriveRoads.parse("not json".encodeToByteArray(), lat, lng, at))
    }

    @Test fun theQueryAsksOverpassAroundTheFixOnly() {
        val query = FreeDriveRoads.query(lat, lng)
        assertTrue(query.contains("(around:60,$lat,$lng)"), query)
        assertTrue(query.contains("way[\"highway\"][\"maxspeed\"]"), query)
        assertTrue(query.contains("way[\"highway\"]"), query)
        assertTrue(query.contains("out tags geom"), query)
        assertFalse(query.contains("node["), "a free-drive lookup does not ask for camera nodes")
    }

    @Test fun theLookupReadsTheOverpassReplyItAskedFor() = runTest {
        val http = OneReplyHttp(
            """{"elements":[{"tags":{"highway":"secondary","name":"Van Ness Avenue","ref":"US 101","maxspeed":"25 mph"},
            "geometry":[{"lat":37.7749,"lon":-122.4195},{"lat":37.7749,"lon":-122.4193}]}]}""")
        val lookup = FreeDriveRoadLookup(http, nowMillis = { 1_791_460_000_000L })
        val road = assertNotNull(lookup.roadAt(lat, lng))
        assertEquals("Van Ness Avenue", road.name)
        assertEquals(25 * 1.609344, assertNotNull(road.limitKmh), 1e-6)
        assertEquals(1, http.requests.size)
        assertTrue(http.requests.first().url.contains("overpass"))
    }
}

private fun way(
    highway: String,
    offset: Double,
    name: String? = null,
    ref: String? = null,
    maxspeed: String? = null,
): String {
    val tags = buildString {
        append("\"highway\":\"$highway\"")
        if (name != null) append(",\"name\":\"$name\"")
        if (ref != null) append(",\"ref\":\"$ref\"")
        if (maxspeed != null) append(",\"maxspeed\":\"$maxspeed\"")
    }
    return "{\"tags\":{$tags},\"geometry\":[{\"lat\":${37.7749 + offset},\"lon\":-122.4195}," +
        "{\"lat\":${37.7749 + offset},\"lon\":-122.4193}]}"
}

private fun reply(vararg ways: String): String = "{\"elements\":[${ways.joinToString(",")}]}"

private class OneReplyHttp(private val body: String) : VelaHttp {
    val requests = ArrayList<HttpRequest>()

    override fun execute(
        request: HttpRequest,
        callback: (HttpResponse?, Throwable?) -> Unit,
    ): app.vela.core.platform.Cancellable {
        requests += request
        callback(HttpResponse(200, emptyList(), body.encodeToByteArray(), request.url), null)
        return app.vela.core.platform.Cancellable {}
    }
}
