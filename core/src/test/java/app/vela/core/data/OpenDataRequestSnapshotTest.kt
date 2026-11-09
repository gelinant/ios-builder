package app.vela.core.data

import app.vela.core.di.CoreModule
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPOutputStream

/**
 * The requests of the NDW bridge feed and the UK fuel price store (method, URL, headers, call,
 * connect, read and write timeouts), what they make of canned replies and the files the store
 * leaves, against `open_data_requests_snapshot.txt`. Taken before both moved to the VelaHttp
 * seam, so the move is checked to send the same requests.
 */
class OpenDataRequestSnapshotTest {
    @get:Rule val tmp = TemporaryFolder()

    private val seen = mutableListOf<String>()
    @Volatile private var code = 200

    private fun gz(bytes: ByteArray) = ByteArrayOutputStream().also { o -> GZIPOutputStream(o).use { it.write(bytes) } }.toByteArray()

    private val feed = gz(
        """<?xml version="1.0" encoding="UTF-8"?>
        <mc:messageContainer xmlns:sit="s" xmlns:mc="m" xmlns:loc="l" xmlns:com="c"><mc:payload>
        <sit:situation id="A"><sit:situationRecord id="A_01">
        <com:overallStartTime>2026-10-09T09:23:00Z</com:overallStartTime><com:overallEndTime>2026-10-09T09:29:00.5Z</com:overallEndTime>
        <loc:latitude>52.3731</loc:latitude><loc:longitude>4.8922</loc:longitude>
        <sit:operatorActionStatus>approved</sit:operatorActionStatus>
        <sit:generalNetworkManagementType>bridgeSwingInOperation</sit:generalNetworkManagementType>
        </sit:situationRecord></sit:situation>
        <sit:situation id="B"><sit:situationRecord id="B_01">
        <com:overallStartTime>2026-10-09T08:05:12Z</com:overallStartTime>
        <loc:latitude>52.3600</loc:latitude><loc:longitude>4.9000</loc:longitude>
        <sit:operatorActionStatus>implemented</sit:operatorActionStatus>
        <sit:generalNetworkManagementType>bridgeSwingInOperation</sit:generalNetworkManagementType>
        </sit:situationRecord></sit:situation>
        </mc:payload></mc:messageContainer>""".toByteArray(),
    )

    private val csv = javaClass.getResourceAsStream("/fuel/fuel-gb-sample.csv")!!.readBytes()
    private val fuelData = gz(csv)
    private val manifest = run {
        val sha = MessageDigest.getInstance("SHA-256").digest(fuelData).joinToString("") { "%02x".format(it) }
        """{"version":1,"file":"fuel-gb.csv.gz","fileSha256":"$sha","stations":5}"""
    }

    private val capture = Interceptor { chain ->
        val r = chain.request()
        val line = describe(r, chain.call().timeout().timeoutNanos(), chain.connectTimeoutMillis(), chain.readTimeoutMillis(), chain.writeTimeoutMillis())
        synchronized(seen) { seen += line }
        val url = r.url.toString()
        val body = when {
            url.endsWith(".xml.gz") -> feed
            url.endsWith(".json") -> manifest.toByteArray()
            else -> fuelData
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

    private val client: OkHttpClient = CoreModule.okHttpClient().newBuilder().addInterceptor(capture).build()
    // UkFuelPrices' download client.
    private val fuelClient: OkHttpClient = client.newBuilder().callTimeout(java.time.Duration.ZERO).readTimeout(java.time.Duration.ofSeconds(60)).build()

    private suspend fun section(name: String, block: suspend () -> Any?): String {
        synchronized(seen) { seen.clear() }
        val result = block()
        val lines = synchronized(seen) { seen.toList() }
        return "## $name\n" + lines.joinToString("\n") + "\n=> $result\n"
    }

    private fun listing(dir: File) = dir.listFiles()!!.sortedBy { it.name }.joinToString(", ") { "${it.name} ${it.length()}" }

    @Test fun `the open data requests stay the same`() = runBlocking {
        val dir = tmp.newFolder("fuelgb")
        var clock = 1_000_000_000L
        val store = FuelGbStore(app.vela.core.platform.AndroidPlatformFiles(tmp.root, tmp.root, tmp.root), { dir.path }, app.vela.core.platform.OkHttpVelaHttp(fuelClient), baseUrl = "https://example.org/fuel-gb/", nowMs = { clock })
        val text = buildString {
            code = 200
            append(section("ndw fetch") { NdwBridgeOpenings.fetch(OpenServicesHttp.ndw(client)) })
            append(section("fuel first ensure") { "${store.ensure()} ${store.current?.size} [${listing(dir)}]" })
            clock += FuelGbStore.CHECK_EVERY_MS
            append(section("fuel recheck") { "${store.ensure()} ${store.current?.size} [${listing(dir)}]" })
            code = 503
            append(section("ndw refused") { NdwBridgeOpenings.fetch(OpenServicesHttp.ndw(client)) })
            clock += FuelGbStore.CHECK_EVERY_MS
            append(section("fuel refused") { "${store.ensure()} ${store.current?.size} [${listing(dir)}]" })
            code = 200
        }
        val expected = javaClass.getResourceAsStream("/open_data_requests_snapshot.txt")?.bufferedReader()?.readText()
        if (expected != text) {
            File("build").mkdirs()
            File("build/open_data_requests_snapshot.txt").writeText(text)
        }
        assertEquals("open data requests changed; new text in core/build/open_data_requests_snapshot.txt", expected, text)
    }
}
