package app.vela.core.data.transit

import app.vela.core.data.ClockFormat
import app.vela.core.di.CoreModule
import app.vela.core.model.LatLng
import app.vela.core.platform.AndroidPlatformLocale
import app.vela.core.platform.JvmTextNormalizer
import app.vela.core.platform.OkHttpVelaHttp
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Every request [Transitous] makes (method, URL, headers, call, connect, read and write timeouts)
 * and what it makes of canned replies, against `transitous_requests_snapshot.txt`. Taken before
 * the client moved to the VelaHttp seam, so the move is checked to send the same requests and
 * parse the same boards, trips and plans. The line fetch went through a client derived with a
 * 40 s call timeout; the request now carries the 40 s itself.
 */
class TransitousRequestSnapshotTest {

    private val seen = mutableListOf<String>()
    @Volatile private var code = 200

    private val stops = """[
        {"name":"Davis Depot","stopId":"a1","parentId":"p1","lat":38.5449,"lon":-121.7405,"modes":["BUS"]},
        {"name":"DAVIS DEPOT","stopId":"a2","lat":38.5450,"lon":-121.7404,"modes":["BUS","RAIL"]},
        {"name":"Covell & Anderson","stopId":"c1","lat":38.5600,"lon":-121.7500}
    ]"""

    private fun stopTimes(id: String) = """{"stopTimes":[
        {"place":{"departure":"2026-09-28T22:34:00Z","scheduledDeparture":"2026-09-28T22:31:00Z","tz":"America/Los_Angeles"},"mode":"BUS","realTime":true,"headsign":"Downtown $id","routeShortName":"42","routeColor":"00aa00","tripId":"t-$id"},
        {"place":{"departure":"2026-03-08T09:59:00Z","tz":null},"mode":"TRAM","headsign":"Uptown","routeShortName":"7","tripId":"u-$id"},
        {"place":{"scheduledDeparture":"2026-10-25T00:30:00Z","tz":"Mars/Base"},"mode":"SUBWAY","headsign":"Uptown","routeShortName":"7"},
        {"place":{"departure":"2026-10-25T01:30:00Z","cancelled":true},"mode":"BUS","routeShortName":"9"}
    ]}"""

    private val trip = """{"legs":[{"mode":"BUS","headsign":"Downtown","routeShortName":"42","routeColor":"#00aa00","realTime":true,
        "from":{"name":"Davis Depot","stopId":"a1","lat":38.5449,"lon":-121.7405,"departure":"2026-09-28T22:34:00Z","scheduledDeparture":"2026-09-28T22:31:00Z","tz":"America/Los_Angeles"},
        "intermediateStops":[{"name":"Covell","stopId":"c1","lat":38.5600,"lon":-121.7500,"arrival":"2026-09-28T22:40:00Z","tz":"America/Los_Angeles","cancelled":true}],
        "to":{"name":"Sacramento","stopId":"s1","lat":38.5816,"lon":-121.4944,"arrival":"2026-09-28T23:10:00Z","scheduledArrival":"2026-09-28T23:12:00Z","tz":"America/Los_Angeles","stopCode":"SAC"}}]}"""

    private val plan: String = File("../core-common/src/jvmTest/resources/transitous/plan-davis-sacramento.json").readText()

    private val capture = Interceptor { chain ->
        val r = chain.request()
        val line = describe(r, chain.call().timeout().timeoutNanos(), chain.connectTimeoutMillis(), chain.readTimeoutMillis(), chain.writeTimeoutMillis())
        synchronized(seen) { seen += line }
        val path = r.url.encodedPath
        val body = when {
            path.endsWith("/map/stops") -> stops
            path.endsWith("/stoptimes") -> stopTimes(r.url.queryParameter("stopId") ?: "")
            path.endsWith("/trip") -> trip
            path.endsWith("/plan") -> plan
            else -> "{}"
        }
        Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(code).message("X")
            .body(body.toResponseBody(null)).build()
    }

    private fun describe(r: Request, callNanos: Long, connect: Int, read: Int, write: Int): String {
        val head = "${r.method} ${r.url} body=${r.body != null}" +
            " call=${TimeUnit.NANOSECONDS.toMillis(callNanos)} connect=$connect read=$read write=$write"
        val lines = (0 until r.headers.size).map { "  ${r.headers.name(it)}: ${r.headers.value(it).replace(app.vela.core.VelaConfig.VELA_UA, "<VELA_UA>")}" }
        return (listOf(head) + lines).joinToString("\n")
    }

    private val client = TransitousHttp(
        OkHttpVelaHttp(CoreModule.okHttpClient().newBuilder().addInterceptor(capture).build()),
        AndroidPlatformLocale, JvmTextNormalizer,
    )

    private val davis = LatLng(38.5449, -121.7405)
    private val sacramento = LatLng(38.5816, -121.4944)
    private val at = 1_790_634_840L

    private suspend fun section(name: String, sorted: Boolean = false, block: suspend () -> Any?): String {
        synchronized(seen) { seen.clear() }
        val result = block()
        val lines = synchronized(seen) { seen.toList() }
        return "## $name\n" + (if (sorted) lines.sorted() else lines).joinToString("\n") + "\n=> $result\n"
    }

    @Test fun `the transitous requests and their parses stay the same`() = runBlocking {
        val oldLocale = Locale.getDefault()
        val oldZone = TimeZone.getDefault()
        val text = try {
            Locale.setDefault(Locale.JAPAN)
            TimeZone.setDefault(TimeZone.getTimeZone("Europe/Paris"))
            buildString {
                code = 200
                append(section("stopsInBox") { Transitous.stopsInBox(client, 38.54, -121.75, 38.55, -121.73) })
                append(section("stopsNear") { Transitous.stopsNear(client, davis.lat, davis.lng) })
                append(section("linesInBox") { Transitous.linesInBox(client, 38.5, -121.8, 38.55, -121.75, 14) })
                append(section("stopTimes") { Transitous.stopTimes(client, "us-Amtrak_DAV/1 2", timeEpochSec = at) })
                append(section("board", sorted = true) { Transitous.board(client, davis.lat, davis.lng, at) })
                ClockFormat.use24h = true
                append(section("boardFor 24h", sorted = true) {
                    Transitous.boardFor(client, Transitous.MapStop(name = "Davis Depot", stopId = "a1", parentId = "p1", siblingIds = listOf("a2", "x&y")))
                })
                ClockFormat.use24h = false
                append(section("tripStops") { Transitous.tripStops(client, "t-p1/é", davis.lat, davis.lng, at) })
                append(section("plan leave now") { Transitous.plan(client, davis, sacramento) })
                append(section("plan depart at") { Transitous.plan(client, davis, sacramento, timeMode = 1, timeEpochSec = at, prefer = setOf(0, 2)) })
                Locale.setDefault(Locale("iw", "IL"))
                TimeZone.setDefault(TimeZone.getTimeZone("Asia/Kolkata"))
                ClockFormat.use24h = true
                append(section("plan arrive by 24h") { Transitous.plan(client, davis, sacramento, timeMode = 2, timeEpochSec = at, prefer = setOf(1, 3), max = 3) })
                ClockFormat.use24h = false
                append(section("legShape") { Transitous.legShape(client, davis, sacramento, at) })
                append(section("legShape no time") { Transitous.legShape(client, davis, sacramento, null) })
                code = 503
                append(section("stopsInBox refused") { Transitous.stopsInBox(client, 38.54, -121.75, 38.55, -121.73) })
                append(section("board refused") { Transitous.board(client, davis.lat, davis.lng) })
                append(section("linesInBox refused") { Transitous.linesInBox(client, 38.5, -121.8, 38.55, -121.75, 8) })
                append(section("plan refused") { Transitous.plan(client, davis, sacramento) })
                code = 200
            }
        } finally {
            Locale.setDefault(oldLocale)
            TimeZone.setDefault(oldZone)
            ClockFormat.use24h = false
        }
        val expected = javaClass.getResourceAsStream("/transitous_requests_snapshot.txt")?.bufferedReader()?.readText()
        if (expected != text) {
            File("build").mkdirs()
            File("build/transitous_requests_snapshot.txt").writeText(text)
        }
        assertEquals("transitous requests changed; new text in core/build/transitous_requests_snapshot.txt", expected, text)
    }
}
