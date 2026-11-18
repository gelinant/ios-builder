package app.vela.core.config

import app.vela.core.VelaConfig
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.FileEntry
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.JsEngine
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NormalForm
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlinx.coroutines.test.runTest

/** [CalibrationStore] and [JsTransforms] over in-memory seams. A signature is valid when it reads
 *  `ok:` followed by the content, under the pinned key only. */
class CalibrationStoreTest {
    private val raw = "https://raw.githubusercontent.com/PimpinPumpkin/Vela/main/calibration.json"
    private val site = "https://velamaps.org/calibration.json"

    @AfterTest fun reset() {
        CalibrationStore(graph(MemFiles(), FakeHttp(emptyMap())), FakeSignatures)
        VelaLinks.overrides = emptyMap()
    }

    @Test fun `with no cache the compiled default is active`() {
        val store = CalibrationStore(graph(MemFiles(), FakeHttp(emptyMap())), FakeSignatures)
        assertSame(Calibration.DEFAULT, store.current())
        assertSame(Calibration.DEFAULT, CalibrationStore.latest)
    }

    @Test fun `a signed newer bundle is adopted and cached`() = runTest {
        val files = MemFiles()
        val http = FakeHttp(mapOf(raw to bundle(7), "$raw.sig" to sign(bundle(7))))
        val store = CalibrationStore(graph(files, http), FakeSignatures)
        store.refresh()
        assertEquals(7, store.current().version)
        assertEquals(7, CalibrationStore.latest.version)
        assertEquals(bundle(7), files.data["/files/calibration.json"])
        assertEquals(sign(bundle(7)), files.data["/files/calibration.json.sig"])
        assertEquals(listOf(raw, "$raw.sig"), http.asked)
        assertEquals(VelaConfig.VELA_UA, http.userAgents.distinct().single())
    }

    @Test fun `refresh runs once`() = runTest {
        val http = FakeHttp(mapOf(raw to bundle(7), "$raw.sig" to sign(bundle(7))))
        val store = CalibrationStore(graph(MemFiles(), http), FakeSignatures)
        store.refresh()
        store.refresh()
        assertEquals(2, http.asked.size)
    }

    @Test fun `a bad signature on GitHub falls back to the site copy`() = runTest {
        val http = FakeHttp(
            mapOf(raw to bundle(7), "$raw.sig" to "forged", site to bundle(8), "$site.sig" to sign(bundle(8))),
        )
        val store = CalibrationStore(graph(MemFiles(), http), FakeSignatures)
        store.refresh()
        assertEquals(8, store.current().version)
        assertEquals(listOf(raw, "$raw.sig", site, "$site.sig"), http.asked)
    }

    @Test fun `an endpoint off google is refused`() = runTest {
        val evil = """{"version": 9, "searchEndpoint": "https://evil.example/search"}"""
        val files = MemFiles()
        val store = CalibrationStore(graph(files, FakeHttp(mapOf(raw to evil, "$raw.sig" to sign(evil)))), FakeSignatures)
        store.refresh()
        assertSame(Calibration.DEFAULT, store.current())
        assertNull(files.data["/files/calibration.json"])
    }

    @Test fun `a cached bundle is checked again at construction`() {
        val good = MemFiles().apply {
            data["/files/calibration.json"] = bundle(5)
            data["/files/calibration.json.sig"] = sign(bundle(5))
        }
        assertEquals(5, CalibrationStore(graph(good, FakeHttp(emptyMap())), FakeSignatures).current().version)
        val tampered = MemFiles().apply {
            data["/files/calibration.json"] = bundle(6)
            data["/files/calibration.json.sig"] = sign(bundle(5))
        }
        assertSame(Calibration.DEFAULT, CalibrationStore(graph(tampered, FakeHttp(emptyMap())), FakeSignatures).current())
    }

    @Test fun `transforms run through the engine with the 2 s limit and fall back on blank`() {
        val js = """{"version": 5, "transformsJs": "function transformPlaces(j){ return j; }"}"""
        val files = MemFiles().apply {
            data["/files/calibration.json"] = js
            data["/files/calibration.json.sig"] = sign(js)
        }
        val store = CalibrationStore(graph(files, FakeHttp(emptyMap())), FakeSignatures)
        val engine = FakeJs(" ")
        val places = listOf(Place(id = "a", name = "Davis", location = LatLng(38.5449, -121.7405)))
        assertSame(places, JsTransforms(store, engine).refineSearch(places))
        assertEquals(listOf("transformPlaces" to JsTransforms.MAX_RUN_MS), engine.calls)
        assertNull(JsTransforms(store, FakeJs(null)).searchOverride("[]"))
    }

    private fun bundle(version: Int) = """{"version": $version}"""

    private fun sign(content: String) = "ok:$content"

    private object FakeSignatures : SignatureVerifier {
        override fun verify(content: ByteArray, signatureBase64: String, publicKeyBase64: String): Boolean =
            publicKeyBase64 == CalibrationStore.PINNED_PUBLIC_KEY && signatureBase64.trim() == "ok:" + content.decodeToString()
    }

    private class FakeJs(private val reply: String?) : JsEngine {
        val calls = mutableListOf<Pair<String, Long>>()
        override fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String? {
            calls += function to timeLimitMillis
            return reply
        }
    }

    private class FakeHttp(private val replies: Map<String, String>) : VelaHttp {
        val asked = mutableListOf<String>()
        val userAgents = mutableListOf<String>()
        override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
            asked += request.url
            request.headers.filter { it.name == "User-Agent" }.forEach { userAgents += it.value }
            val text = replies[request.url]
            if (text == null) {
                callback(null, IllegalStateException("unreachable"))
            } else {
                callback(HttpResponse(200, emptyList(), text.encodeToByteArray(), request.url), null)
            }
            return Cancellable { }
        }
    }

    private class MemFiles : PlatformFiles {
        val data = mutableMapOf<String, String>()
        override val filesDir = "/files"
        override val cacheDir = "/cache"
        override val noBackupDir = "/nobackup"
        override fun exists(path: String) = path in data
        override fun isDirectory(path: String) = false
        override fun size(path: String) = data[path]?.length?.toLong() ?: 0L
        override fun lastModifiedMillis(path: String) = 0L
        override fun list(path: String): List<FileEntry>? = null
        override fun mkdirs(path: String) = true
        override fun readBytes(path: String) = readText(path).encodeToByteArray()
        override fun readText(path: String) = data[path] ?: throw IllegalStateException("missing $path")
        override fun writeBytes(path: String, bytes: ByteArray) = writeText(path, bytes.decodeToString())
        override fun writeText(path: String, text: String) { data[path] = text }
        override fun writeTextAtomic(path: String, text: String) = writeText(path, text)
        override fun rename(from: String, to: String) = data.remove(from)?.let { data[to] = it; true } ?: false
        override fun delete(path: String) = data.remove(path) != null
        override fun deleteRecursively(path: String) = true
    }

    private fun graph(files: PlatformFiles, http: VelaHttp) = CoreGraph(
        log = object : Log {
            override fun isLoggable(tag: String, level: LogLevel) = false
            override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
        },
        clock = object : Clock {
            override fun nowMillis() = 0L
            override fun elapsedRealtimeMillis() = 0L
            override fun monotonicNanos() = 0L
        },
        keyValues = object : KeyValueStores {
            override fun open(name: String) = error("unused")
        },
        files = files,
        http = http,
        text = object : TextNormalizer {
            override fun normalize(text: String, form: NormalForm) = text
        },
        locale = object : PlatformLocale {
            override fun defaultTag() = "en-US"
            override fun defaultLanguage() = "en"
            override fun preferredTags() = listOf("en-US")
            override fun systemTags() = listOf("en-US")
        },
    )
}
