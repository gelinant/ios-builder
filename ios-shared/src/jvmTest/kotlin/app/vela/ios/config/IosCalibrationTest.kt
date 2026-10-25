package app.vela.ios.config

import app.vela.core.config.Calibration
import app.vela.core.config.CalibrationStore
import app.vela.core.config.VelaLinks
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.FileEntry
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.JsEngine
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.NormalForm
import app.vela.core.platform.TextNormalizer
import app.vela.ios.search.FakeHttp
import app.vela.ios.search.FakeLocale
import app.vela.ios.search.IosGoogleSearch
import app.vela.ios.search.SearchFixture
import app.vela.ios.search.ok
import java.io.File
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest

/** The live calibration over the repository's real signed `calibration.json`, as the iOS app runs it. */
class IosCalibrationTest {
    private val body = File("../calibration.json").readText()
    private val sig = File("../calibration.json.sig").readText()
    private val bodyVersion = Regex("\"version\"\\s*:\\s*(\\d+)").find(body)!!.groupValues[1].toInt()
    private val raw = VelaLinks.default(VelaLinks.CALIBRATION)
    private val site = VelaLinks.default(VelaLinks.CALIBRATION_MIRROR)
    private val logs = mutableListOf<String>()

    @BeforeTest @AfterTest fun resetLinks() {
        VelaLinks.overrides = emptyMap()
    }

    @Test fun buildingDoesNothingStartAdoptsTheSignedBundleAndCachesIt() = runTest {
        val files = MemoryFiles()
        val http = FakeHttp { r -> serve(r.url, mapOf(raw to body, "$raw.sig" to sig)) }
        val cal = IosCalibration(graph(files, http), JvmVerifier, NoJs, this)
        assertEquals(0, http.requests.size)
        assertEquals(0, cal.version.value)
        assertEquals(Calibration.DEFAULT.version, cal.current().version)
        assertNull(cal.transforms)

        cal.start()
        assertEquals(Calibration.DEFAULT.version, cal.version.value)
        cal.refreshed.first { it }
        assertTrue(bodyVersion >= 27)
        assertEquals(bodyVersion, cal.version.value)
        assertEquals(bodyVersion, cal.current().version)
        assertEquals(listOf(raw, "$raw.sig"), http.requests.map { it.url })
        assertTrue(http.requests.all { r -> r.headers.any { it.name == "User-Agent" && it.value.startsWith("VelaMaps/") } })
        assertTrue(logs.any { it.endsWith("version $bodyVersion") })
        assertTrue(logs.none { Regex("-?\\d+\\.\\d{3,}").containsMatchIn(it) }, "a log line holds a coordinate-like number")

        // The next launch starts from the verified cache before any network.
        VelaLinks.overrides = emptyMap()
        val offline = FakeHttp { throw java.io.IOException("offline") }
        val next = IosCalibration(graph(files, offline), JvmVerifier, NoJs, this)
        next.start()
        assertEquals(bodyVersion, next.version.value)
        next.refreshed.first { it }
        assertEquals(bodyVersion, next.current().version)
    }

    @Test fun githubDownFallsBackToTheSiteCopy() = runTest {
        val http = FakeHttp { r -> serve(r.url, mapOf(site to body, "$site.sig" to sig)) }
        val cal = IosCalibration(graph(MemoryFiles(), http), JvmVerifier, NoJs, this)
        cal.start()
        cal.refreshed.first { it }
        assertEquals(bodyVersion, cal.current().version)
        assertEquals(raw, http.requests.first().url)
        assertEquals(site, http.requests.last { !it.url.endsWith(".sig") }.url)
    }

    @Test fun aTamperedBundleIsRefused() = runTest {
        val tampered = body.replaceFirst("\"version\": $bodyVersion", "\"version\": ${bodyVersion + 1}")
        val http = FakeHttp { r -> serve(r.url, mapOf(raw to tampered, "$raw.sig" to sig, site to tampered, "$site.sig" to sig)) }
        val files = MemoryFiles()
        val cal = IosCalibration(graph(files, http), JvmVerifier, NoJs, this)
        cal.start()
        cal.refreshed.first { it }
        assertEquals(Calibration.DEFAULT.version, cal.current().version)
        assertTrue(files.map.isEmpty())
    }

    private fun serve(url: String, table: Map<String, String>): HttpResponse =
        table[url]?.let { ok(it, url) } ?: HttpResponse(404, emptyList(), ByteArray(0), url)

    private fun graph(files: PlatformFiles, http: FakeHttp) = CoreGraph(
        log = object : Log {
            override fun isLoggable(tag: String, level: LogLevel) = true
            override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {
                logs += message
            }
        },
        clock = object : Clock {
            override fun nowMillis() = 0L
            override fun elapsedRealtimeMillis() = 0L
            override fun monotonicNanos() = 0L
        },
        keyValues = object : KeyValueStores {
            override fun open(name: String): KeyValueStore = throw UnsupportedOperationException()
        },
        files = files,
        http = http,
        text = object : TextNormalizer {
            override fun normalize(text: String, form: NormalForm) = text
        },
        locale = FakeLocale("en-US"),
    )

    /** Android's verifier (`JvmSignatureVerifier` in `:core`), the reference the Swift one matches. */
    private object JvmVerifier : SignatureVerifier {
        override fun verify(content: ByteArray, signatureBase64: String, publicKeyBase64: String): Boolean = runCatching {
            val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(publicKeyBase64)))
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(key)
                update(content)
                verify(Base64.getDecoder().decode(signatureBase64.trim()))
            }
        }.getOrDefault(false)
    }

    private object NoJs : JsEngine {
        override fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String? = null
    }

    @Test fun searchReadsTheLiveBundleAndItsTransforms() = runTest {
        val bundle = "{\"version\": 99, \"transformsJs\": \"function transformPlaces(s) { return s; }\"}"
        val js = RecordingJs()
        val http = FakeHttp { r ->
            when {
                r.url == raw || r.url == "$raw.sig" -> ok(if (r.url == raw) bundle else "sig", r.url)
                r.url.contains("/search?") -> ok(SearchFixture.reply(3), r.url)
                else -> ok("", r.url)
            }
        }
        val cal = IosCalibration(graph(MemoryFiles(), http), AnySignature, js, this)
        val search = IosGoogleSearch(http, FakeLocale("en-US"), calibration = cal::current, transforms = { cal.transforms })
        cal.start()
        cal.refreshed.first { it }
        assertEquals(99, cal.current().version)
        val result = search.search("coffee", IosGoogleSearch.DEFAULT_VIEWPORT, null, null, null)
        assertEquals(3, result.places.size)
        assertEquals(listOf("parseSearch", "transformPlaces"), js.calls)
    }

    private object AnySignature : SignatureVerifier {
        override fun verify(content: ByteArray, signatureBase64: String, publicKeyBase64: String) = true
    }

    /** Records the hooks called and answers null, so the compiled result stands. */
    private class RecordingJs : JsEngine {
        val calls = mutableListOf<String>()
        override fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String? {
            calls += function
            return null
        }
    }

    @Test fun thePinnedKeyIsAnUncompressedP256Point() {
        val spki = Base64.getDecoder().decode(CalibrationStore.PINNED_PUBLIC_KEY)
        assertEquals(91, spki.size)
        assertEquals(0x04, spki[26].toInt())
    }
}

/** [PlatformFiles] in memory, enough for [CalibrationStore]. */
class MemoryFiles : PlatformFiles {
    val map = mutableMapOf<String, String>()
    override val filesDir = "/files"
    override val cacheDir = "/cache"
    override val noBackupDir = "/nobackup"
    override fun exists(path: String) = path in map
    override fun isDirectory(path: String) = false
    override fun size(path: String) = map[path]?.length?.toLong() ?: 0L
    override fun lastModifiedMillis(path: String) = 0L
    override fun list(path: String): List<FileEntry>? = null
    override fun mkdirs(path: String) = true
    override fun readBytes(path: String) = readText(path).encodeToByteArray()
    override fun readText(path: String) = map[path] ?: throw java.io.IOException("missing $path")
    override fun writeBytes(path: String, bytes: ByteArray) { map[path] = bytes.decodeToString() }
    override fun writeText(path: String, text: String) { map[path] = text }
    override fun writeTextAtomic(path: String, text: String) { map[path] = text }
    override fun rename(from: String, to: String) = map.remove(from)?.let { map[to] = it; true } ?: false
    override fun delete(path: String) = map.remove(path) != null
    override fun deleteRecursively(path: String) = true
}
