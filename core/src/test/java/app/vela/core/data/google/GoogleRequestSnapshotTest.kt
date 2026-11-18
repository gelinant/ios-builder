package app.vela.core.data.google

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import app.vela.core.config.Calibration
import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.RouteEngine
import app.vela.core.di.CoreModule
import app.vela.core.diag.DiagLog
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.TravelMode
import app.vela.core.net.AgedSession
import app.vela.core.net.GoogleTransport
import app.vela.core.net.GoogleUsage
import app.vela.core.platform.AndroidClock
import app.vela.core.platform.AndroidLog
import app.vela.core.platform.AndroidPlatformFiles
import app.vela.core.platform.AndroidPlatformLocale
import app.vela.core.platform.Cancellable
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.JsEngine
import app.vela.core.platform.JvmSignatureVerifier
import app.vela.core.platform.JvmTextNormalizer
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.OkHttpVelaHttp
import app.vela.core.platform.VelaHttp
import java.nio.file.Files
import java.util.concurrent.TimeUnit
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

/**
 * Every kind of Google request the data source sends, as the shared client's last interceptor sees
 * it: method, path, the full header list in order, the counter's purpose tag, the aged-session tag,
 * the body's content type, and the call and read timeouts. The snapshot was taken before the source
 * moved to `:core-common` (lot C-2) and must not change: Google sees exactly what it saw.
 * `{UA}` and `{CH}` stand for the compiled calibration's user agent and client hints.
 */
class GoogleRequestSnapshotTest {

    private val seen = mutableListOf<String>()

    private val capture = Interceptor { chain ->
        val r = chain.request()
        synchronized(seen) { seen += describe(r, chain.call().timeout().timeoutNanos(), chain.readTimeoutMillis()) }
        Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(200).message("OK")
            .body("".toResponseBody(null)).build()
    }

    private fun describe(r: Request, callNanos: Long, readMs: Int): String {
        val cal = Calibration.DEFAULT
        val head = "${r.method} host=${r.url.host} ${r.url.encodedPath} kind=${r.tag(GoogleUsage.Kind::class.java)?.name ?: "-"}" +
            " aged=${r.tag(AgedSession::class.java) != null} body=${r.body?.contentType() ?: "-"}" +
            " call=${TimeUnit.NANOSECONDS.toMillis(callNanos)} read=$readMs"
        val lines = (0 until r.headers.size).map { "${r.headers.name(it)}: ${r.headers.value(it)}" }
        return (listOf(head) + lines).joinToString("\n")
            .replace(cal.userAgent, "{UA}").replace(cal.secChUa, "{CH}")
    }

    private val client: OkHttpClient = CoreModule.okHttpClient().newBuilder().addInterceptor(capture).build()

    private val store = CalibrationStore(
        CoreGraph(
            log = AndroidLog,
            clock = AndroidClock,
            keyValues = object : KeyValueStores { override fun open(name: String) = error("unused") },
            files = Files.createTempDirectory("cal").toFile().let { AndroidPlatformFiles(it, it, it) },
            http = object : VelaHttp {
                override fun execute(request: app.vela.core.platform.HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
                    callback(HttpResponse(404, emptyList(), ByteArray(0), request.url), null)
                    return Cancellable { }
                }
            },
            text = JvmTextNormalizer,
            locale = AndroidPlatformLocale,
        ),
        JvmSignatureVerifier,
    )

    private val noJs = object : JsEngine {
        override fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String? = null
    }

    /** A Context whose preferences answer every default, so [DiagLog] stays off. */
    private val context: Context = object : ContextWrapper(null) {
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences = NoPrefs
    }

    private val noRouting = object : RouteEngine {
        override fun isReady(mode: TravelMode) = false
        override fun route(
            origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean, avoidHighways: Boolean,
            avoidFerries: Boolean, departBearingDeg: Double?, maxMs: Long?,
        ): List<Route> = emptyList()
    }

    private fun source(c: OkHttpClient = client): GoogleMapsDataSource {
        val graph = CoreGraph(
            log = AndroidLog,
            clock = AndroidClock,
            keyValues = object : KeyValueStores { override fun open(name: String) = error("unused") },
            files = AndroidPlatformFiles(java.io.File("."), java.io.File("."), java.io.File(".")),
            http = OkHttpVelaHttp(c),
            text = JvmTextNormalizer,
            locale = AndroidPlatformLocale,
        )
        val session = GoogleSession(graph.http, store, ChromeIdentity { store.current() })
        return AndroidGoogleSource.create(c, graph, session, store, JsTransforms(store, noJs), DiagLog(context), noRouting)
    }

    private fun take(step: String): String = synchronized(seen) {
        ("# $step\n" + seen.joinToString("\n")).also { seen.clear() }
    }

    /** The request blocks of [lines] whose first line names a Google host. */
    private fun dropForeign(lines: List<String>): String {
        val out = mutableListOf<String>()
        var keep = true
        for (line in lines) {
            if (line.startsWith("GET ") || line.startsWith("POST ")) keep = "host=www.google.com" in line
            if (line.startsWith("# ") || keep) out += line
        }
        return out.joinToString("\n")
    }

    @Test fun `the google requests keep their headers, tags and timeouts`() = runBlocking {
        val src = source()
        val at = LatLng(38.5449, -121.7405)
        val steps = mutableListOf<String>()
        runCatching { src.search("coffee", at) }
        steps += take("search")
        runCatching { src.suggest("cof", at) }
        steps += take("suggest")
        runCatching { src.reviewFeed("0x1:0x2") }
        steps += take("review feed")
        runCatching { src.placePhotos("0x1:0x2") }
        steps += take("photos")
        runCatching { src.placeDetails(Place(id = "x", name = "Cafe", location = at, address = "1 Main St", featureId = "0x1:0x2")) }
        steps += take("place details")
        runCatching { src.streetView(at) }
        steps += take("street view")
        runCatching { src.streetViewTile("pano", 1, 2, 3) }
        steps += take("street view tile")
        runCatching { src.importMyMap("abc") }
        steps += take("my map")
        runCatching { src.reviews("0x1:0x2") }
        steps += take("reviews")
        runCatching { src.importList("https://www.google.com/maps/placelists/list/abc_D-1") }
        steps += take("shared list by id")
        runCatching { src.importList("https://www.google.com/maps/@38.5,-121.7,14z/data=x") }
        steps += take("shared list page")
        runCatching { src.directions(at, LatLng(38.5816, -121.4944)) }
        // Only Google's: the open router's requests run beside it, in no fixed order.
        steps += dropForeign(take("directions").lines())
        runCatching { src.reverseGeocode(at) }
        steps += take("reverse geocode").replace(app.vela.core.VelaConfig.VELA_UA, "{VELA}")
        assertEquals(SNAPSHOT.trimIndent(), steps.joinToString("\n"))
    }

    @Test fun `the image loader's google requests keep their headers`() {
        val images = OkHttpClient.Builder().addInterceptor(GoogleTransport.imageHeaders).addInterceptor(capture).build()
        images.newCall(Request.Builder().url("https://lh3.googleusercontent.com/p/abc=w400").header("Accept", "image/webp").build()).execute().close()
        assertEquals(IMAGE.trimIndent(), take("image"))
    }

    @Test fun `a post body is the form the page sends`() = runBlocking {
        val bodies = mutableListOf<String>()
        val c = CoreModule.okHttpClient().newBuilder().addInterceptor { chain ->
            val r = chain.request()
            if (r.method == "POST") bodies += Buffer().also { r.body?.writeTo(it) }.readUtf8()
            Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(200).message("OK").body("".toResponseBody(null)).build()
        }.build()
        val src = source(c)
        runCatching { src.reviewFeed("0x1:0x2", pageToken = "tok") }
        assertEquals(1, bodies.size)
        assertEquals(true, bodies[0].startsWith("f.req=%5B%5B%5B%22qv9Egd%22%2C%22"))
        assertEquals(true, bodies[0].endsWith("%22%2Cnull%2C%22generic%22%5D%5D%5D&"))
    }

    private object NoPrefs : SharedPreferences {
        override fun getAll(): MutableMap<String, *> = mutableMapOf<String, Any>()
        override fun getString(key: String?, defValue: String?) = defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?) = defValues
        override fun getInt(key: String?, defValue: Int) = defValue
        override fun getLong(key: String?, defValue: Long) = defValue
        override fun getFloat(key: String?, defValue: Float) = defValue
        override fun getBoolean(key: String?, defValue: Boolean) = defValue
        override fun contains(key: String?) = false
        override fun edit(): SharedPreferences.Editor = error("read only")
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) {}
    }

    private companion object {
        val SNAPSHOT = """
            # search
            GET host=www.google.com /maps kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: document
            Sec-Fetch-Mode: navigate
            Sec-Fetch-Site: none
            GET host=www.google.com /search kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # suggest
            GET host=www.google.com /s kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # review feed
            POST host=www.google.com /maps/_/MapsWizUi/data/batchexecute kind=- aged=true body=application/x-www-form-urlencoded;charset=UTF-8 call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            X-Same-Domain: 1
            x-maps-diversion-context-bin: CAE=
            # photos
            POST host=www.google.com /maps/_/MapsWizUi/data/batchexecute kind=- aged=true body=application/x-www-form-urlencoded;charset=UTF-8 call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            X-Same-Domain: 1
            x-maps-diversion-context-bin: CAE=
            # place details
            GET host=www.google.com /search kind=place details aged=true body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # street view
            POST host=maps.googleapis.com /${'$'}rpc/google.internal.maps.mapsjs.v1.MapsJsInternalService/SingleImageSearch kind=- aged=false body=application/json+protobuf; charset=utf-8 call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            x-user-agent: grpc-web-javascript/0.1
            POST host=maps.googleapis.com /${'$'}rpc/google.internal.maps.mapsjs.v1.MapsJsInternalService/SingleImageSearch kind=- aged=false body=application/json+protobuf; charset=utf-8 call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            x-user-agent: grpc-web-javascript/0.1
            GET host=maps.googleapis.com /maps/api/js/GeoPhotoService.SingleImageSearch kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # street view tile
            GET host=streetviewpixels-pa.googleapis.com /v1/tile kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: image/avif,image/webp,image/apng,*/*;q=0.8
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: image
            Sec-Fetch-Mode: no-cors
            Sec-Fetch-Site: cross-site
            Referer: https://www.google.com/
            # my map
            GET host=www.google.com /maps/d/kml kind=my map aged=false body=- call=90000 read=60000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # reviews
            GET host=www.google.com /maps/preview/review/listentitiesreviews kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # shared list by id
            GET host=www.google.com /maps/preview/entitylist/getlist kind=shared list aged=false body=- call=90000 read=60000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # shared list page
            GET host=www.google.com /maps/@38.5,-121.7,14z/data=x kind=shared list aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # directions
            GET host=www.google.com /maps/preview/directions kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            GET host=www.google.com /maps/preview/directions kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            GET host=www.google.com /maps/preview/directions kind=- aged=false body=- call=12000 read=20000
            User-Agent: {UA}
            Accept: */*
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: empty
            Sec-Fetch-Mode: cors
            Sec-Fetch-Site: same-origin
            Referer: https://www.google.com/maps/
            Downlink: 10
            RTT: 50
            # reverse geocode
            GET host=nominatim.openstreetmap.org /reverse kind=- aged=false body=- call=12000 read=20000
            User-Agent: {VELA}
            Accept-Language: en
        """
        val IMAGE = """
            # image
            GET host=lh3.googleusercontent.com /p/abc=w400 kind=images aged=false body=- call=0 read=10000
            User-Agent: {UA}
            Accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8
            Accept-Language: en-US,en;q=0.9
            Sec-CH-UA: {CH}
            Sec-CH-UA-Mobile: ?0
            Sec-CH-UA-Platform: "Windows"
            Sec-Fetch-Dest: image
            Sec-Fetch-Mode: no-cors
            Sec-Fetch-Site: cross-site
            Referer: https://www.google.com/
        """
    }
}
