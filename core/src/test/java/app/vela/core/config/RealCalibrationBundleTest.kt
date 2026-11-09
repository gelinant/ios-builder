package app.vela.core.config

import app.vela.core.VelaConfig
import app.vela.core.platform.AndroidClock
import app.vela.core.platform.AndroidLog
import app.vela.core.platform.AndroidPlatformFiles
import app.vela.core.platform.AndroidPlatformLocale
import app.vela.core.platform.Cancellable
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.JvmSignatureVerifier
import app.vela.core.platform.JvmTextNormalizer
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.VelaHttp
import java.io.File
import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The published `calibration.json` and its `.sig` at the repo root, through the shared store on
 * the Android seams: the JVM verifier, `java.io.File` storage and a fake transport.
 */
class RealCalibrationBundleTest {
    private val body = rootFile("calibration.json").readText()
    private val sig = rootFile("calibration.json.sig").readText()
    private val dirs = List(3) { Files.createTempDirectory("cal").toFile() }

    @After fun reset() {
        // A store over an empty folder puts the process-wide state back to the compiled default.
        store(dirs[2], http { null })
        VelaLinks.overrides = emptyMap()
        dirs.forEach { it.deleteRecursively() }
    }

    @Test fun `the published bundle verifies against the pinned key and parses`() {
        assertTrue(JvmSignatureVerifier.verify(body.encodeToByteArray(), sig, CalibrationStore.PINNED_PUBLIC_KEY))
        val cal = CalibrationStore.parseBundle(body)
        assertNotNull(cal)
        assertTrue(cal!!.version > Calibration.DEFAULT.version)
    }

    @Test fun `a cached copy of the published bundle is adopted at construction`() {
        File(dirs[0], "calibration.json").writeText(body)
        File(dirs[0], "calibration.json.sig").writeText(sig)
        val store = store(dirs[0], http { null })
        assertEquals(CalibrationStore.parseBundle(body)!!.version, store.current().version)
        assertEquals(store.current().version, CalibrationStore.latest.version)
    }

    @Test fun `refresh falls back to the site copy and caches it`() {
        val asked = mutableListOf<String>()
        val store = store(dirs[1], http { url ->
            asked += url
            when (url) {
                "https://velamaps.org/calibration.json" -> body
                "https://velamaps.org/calibration.json.sig" -> sig
                else -> null
            }
        })
        assertEquals(Calibration.DEFAULT.version, store.current().version)
        runBlocking { store.refresh() }
        assertEquals(CalibrationStore.parseBundle(body)!!.version, store.current().version)
        assertEquals(body, File(dirs[1], "calibration.json").readText())
        assertEquals(sig, File(dirs[1], "calibration.json.sig").readText())
        assertEquals(
            listOf(
                "https://raw.githubusercontent.com/PimpinPumpkin/Vela/main/calibration.json",
                "https://velamaps.org/calibration.json",
                "https://velamaps.org/calibration.json.sig",
            ),
            asked,
        )
    }

    private fun rootFile(name: String): File =
        listOf(File("../$name"), File(name)).first { it.exists() }

    private fun store(dir: File, http: VelaHttp) = CalibrationStore(
        CoreGraph(
            log = AndroidLog,
            clock = AndroidClock,
            keyValues = object : KeyValueStores {
                override fun open(name: String) = error("unused")
            },
            files = AndroidPlatformFiles(dir, dir, dir),
            http = http,
            text = JvmTextNormalizer,
            locale = AndroidPlatformLocale,
        ),
        JvmSignatureVerifier,
    )

    /** Serves [reply] with 200, or 404 when it gives null; checks Vela's own User-Agent. */
    private fun http(reply: (String) -> String?) = object : VelaHttp {
        override fun execute(
            request: app.vela.core.platform.HttpRequest,
            callback: (HttpResponse?, Throwable?) -> Unit,
        ): Cancellable {
            assertEquals(VelaConfig.VELA_UA, request.headers.single { it.name == "User-Agent" }.value)
            val text = reply(request.url)
            callback(HttpResponse(if (text != null) 200 else 404, emptyList(), (text ?: "").encodeToByteArray(), request.url), null)
            return Cancellable { }
        }
    }
}
