package app.vela.core.data

import app.vela.core.di.CoreModule
import app.vela.core.model.LatLng
import app.vela.core.model.TravelMode
import app.vela.core.platform.OkHttpRouteHttp
import app.vela.core.platform.OkHttpVelaHttp
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Every request the open routers make (OSRM in [RouteGeometry], Valhalla in [ValhallaRouter]):
 * method, URL, headers, body, and the call, connect, read and write timeouts each attempt runs
 * with, against `router_requests_snapshot.txt`. Taken before the routers moved to the VelaHttp
 * seam, so the move is checked to send the same requests with the same deadlines.
 */
class RouterRequestSnapshotTest {

    private val seen = mutableListOf<String>()
    @Volatile private var code = 200

    private val capture = Interceptor { chain ->
        val r = chain.request()
        val line = describe(r, chain.call().timeout().timeoutNanos(), chain.connectTimeoutMillis(), chain.readTimeoutMillis(), chain.writeTimeoutMillis())
        synchronized(seen) { seen += line }
        val body = if (r.url.encodedPath.contains("trace") || r.url.host.contains("valhalla")) "{}" else """{"code":"Ok","routes":[],"waypoints":[]}"""
        Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(code).message("X")
            .body(body.toResponseBody(null)).build()
    }

    private fun describe(r: Request, callNanos: Long, connect: Int, read: Int, write: Int): String {
        val body = r.body?.let { b -> Buffer().also { b.writeTo(it) }.readUtf8() }
        val head = "${r.method} ${r.url} type=${r.body?.contentType() ?: "-"}" +
            " call=${TimeUnit.NANOSECONDS.toMillis(callNanos)} connect=$connect read=$read write=$write"
        val lines = (0 until r.headers.size).map { "  ${r.headers.name(it)}: ${r.headers.value(it)}" }
        return (listOf(head) + lines + listOfNotNull(body?.let { "  body $it" })).joinToString("\n")
    }

    private val client: OkHttpClient = CoreModule.okHttpClient().newBuilder().addInterceptor(capture).build()
    private val routeHttp = OkHttpRouteHttp(client)
    private val velaHttp = OkHttpVelaHttp(client)

    private val a = LatLng(38.5449, -121.7405)
    private val v = LatLng(38.5520, -121.7300)
    private val b = LatLng(38.5816, -121.4944)

    private suspend fun section(name: String, sorted: Boolean = false, block: suspend () -> Unit): String {
        synchronized(seen) { seen.clear() }
        block()
        val lines = synchronized(seen) { seen.toList() }
        return "## $name\n" + (if (sorted) lines.sorted() else lines).joinToString("\n") + "\n"
    }

    @Test fun `the router requests keep their urls bodies and timeouts`() = runBlocking {
        val text = buildString {
            code = 200
            append(section("osrm fetchAll") { RouteGeometry.fetchAll(routeHttp, a, b, TravelMode.DRIVE) })
            append(section("osrm route") { RouteGeometry.route(routeHttp, a, b, TravelMode.DRIVE, departBearingDeg = 93.0) })
            append(section("osrm routeVia bounded") {
                RouteGeometry.routeVia(
                    routeHttp, listOf(a, v, b), TravelMode.BICYCLE, strictVias = true, tries = 1, callTimeoutMs = 3_000L,
                    waypointBearings = listOf(null, 45.0, null),
                )
            })
            code = 503
            append(section("osrm route retried under a budget") {
                RouteGeometry.route(routeHttp, a, b, TravelMode.DRIVE, callTimeoutMs = 3_000L, budget = RouteBudget.of(60_000L))
            })
            append(section("osrm route retried") { RouteGeometry.route(routeHttp, a, b, TravelMode.WALK, tries = 2) })
            code = 400
            append(section("osrm route refused") { RouteGeometry.route(routeHttp, a, b, TravelMode.DRIVE) })
            code = 503
            append(section("valhalla route retried") { ValhallaRouter.route(velaHttp, listOf(a, v, b), alternates = true, tries = 2) })
            code = 200
            append(section("valhalla driveRoute") { ValhallaRouter.driveRoute(velaHttp, listOf(a, b), avoidTolls = true, avoidFerries = true) })
            append(section("valhalla edges") { ValhallaRouter.edges(velaHttp, listOf(a, v, b), timeoutMs = 1_000L) })
            append(section("valhalla matchWithEdges", sorted = true) { ValhallaRouter.matchWithEdges(velaHttp, listOf(a, v, b), timeoutMs = 2_000L) })
        }
        val expected = javaClass.getResourceAsStream("/router_requests_snapshot.txt")?.bufferedReader()?.readText()
        if (expected != text) {
            File("build").mkdirs()
            File("build/router_requests_snapshot.txt").writeText(text)
        }
        assertEquals("router requests changed; new text in core/build/router_requests_snapshot.txt", expected, text)
    }
}
