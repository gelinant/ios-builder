package app.vela.core.data

import app.vela.core.VelaConfig
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.platform.joinPath
import app.vela.core.platform.sha256
import app.vela.core.platform.toHex
import app.vela.core.util.ioDispatcher
import kotlin.concurrent.Volatile
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The UK fuel price file on the phone (SPEC 5.8). Nothing is fetched until the app asks, which
 * it does only when a gas station inside [FuelGb.inUk] has no price. Then:
 *
 * - the file on disk is parsed if nothing is in memory;
 * - at most every [CHECK_EVERY_MS] the small manifest is read from the `fuel-gb` release, and the
 *   data file is downloaded only when the manifest names a different one (the release has no
 *   conditional requests to lean on, so the manifest's sha256 is the change test);
 * - a failure is retried after [RETRY_AFTER_MS] and never replaces a good file.
 *
 * [dir] is read on every access (the app passes a folder under `StorageLocation.root`), on
 * [files]. [http] must have no call timeout (requests carry none). Requests carry Vela's own user
 * agent.
 */
class FuelGbStore(
    private val files: PlatformFiles,
    private val dir: () -> String,
    private val http: VelaHttp,
    private val baseUrl: String = BASE_URL,
    private val nowMs: () -> Long,
) {
    companion object {
        val BASE_URL: String get() = app.vela.core.config.VelaLinks.fuelGb()
        const val FOLDER = "fuelgb"
        const val DATA_FILE = "fuel-gb.csv.gz"
        const val MANIFEST_FILE = "fuel-gb-manifest.json"
        private const val CHECKED_FILE = "checked"
        const val CHECK_EVERY_MS = 3L * 60 * 60 * 1000
        const val RETRY_AFTER_MS = 15L * 60 * 1000
        private val FILE_NAME = Regex("[A-Za-z0-9._-]+")
    }

    private val mutex = Mutex()
    @Volatile private var data: FuelGbStations? = null
    @Volatile private var failedAtMs = 0L

    /** The stations in memory, or null until [ensure] has loaded them. */
    val current: FuelGbStations? get() = data

    /** Drop the parsed stations (memory pressure). The next [ensure] reads the file again. */
    fun release() { data = null }

    /**
     * Load the file from disk and fetch a newer one when due. True when [current] changed. Never
     * throws; any failure keeps what is there.
     */
    suspend fun ensure(): Boolean = withContext(ioDispatcher) {
        mutex.withLock {
            try {
                ensureLocked()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                false
            }
        }
    }

    private suspend fun ensureLocked(): Boolean {
        val d = dir().also { files.mkdirs(it) }
        val file = joinPath(d, DATA_FILE)
        var changed = false
        if (data == null && files.exists(file)) {
            data = runCatching { FuelGb.parseGzip(files.readBytes(file)) }.getOrNull()?.takeIf { it.size > 0 }
            changed = data != null
        }
        val now = nowMs()
        val checked = joinPath(d, CHECKED_FILE)
        val lastCheck = runCatching { files.readText(checked).trim().toLong() }.getOrDefault(0L)
        if (files.exists(file) && data != null && now - lastCheck in 0 until CHECK_EVERY_MS) return changed
        if (now - failedAtMs in 0 until RETRY_AFTER_MS) return changed

        val remoteText = get(baseUrl.trimEnd('/') + "/" + MANIFEST_FILE)?.decodeToString()
        val remote = remoteText?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
        if (remote == null) { failedAtMs = now; return changed }
        val localManifest = joinPath(d, MANIFEST_FILE)
        val local = runCatching { Json.parseToJsonElement(files.readText(localManifest)).jsonObject }.getOrNull()
        val remoteSha = remote.str("fileSha256")
        if (files.exists(file) && data != null && remoteSha != null && remoteSha == local?.str("fileSha256")) {
            files.writeText(checked, now.toString())
            return changed
        }
        val name = remote.str("file")?.takeIf { it.matches(FILE_NAME) } ?: DATA_FILE
        val bytes = get(baseUrl.trimEnd('/') + "/" + name)
        if (bytes == null || bytes.size < 2 || bytes[0] != 0x1f.toByte() || bytes[1] != 0x8b.toByte() ||
            (remoteSha != null && sha256(bytes).toHex() != remoteSha)
        ) { failedAtMs = now; return changed }
        val parsed = runCatching { FuelGb.parseGzip(bytes) }.getOrNull()
        if (parsed == null || parsed.size == 0) { failedAtMs = now; return changed }

        // Stage beside the target, move the old copy aside, swap, then drop the old copy.
        val tmp = joinPath(d, "$DATA_FILE.tmp").also { files.writeBytes(it, bytes) }
        val old = joinPath(d, "$DATA_FILE.old").also { files.delete(it) }
        if (files.exists(file) && !files.rename(file, old)) { files.delete(tmp); failedAtMs = now; return changed }
        if (!files.rename(tmp, file)) {
            files.rename(old, file); files.delete(tmp); failedAtMs = now; return changed
        }
        files.delete(old)
        files.writeText(localManifest, remoteText)
        files.writeText(checked, now.toString())
        data = parsed
        return true
    }

    private suspend fun get(url: String): ByteArray? {
        val r = try {
            http.call(HttpRequest(url, headers = listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA))))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            return null
        }
        return if (r.isSuccessful) r.body else null
    }

    private fun JsonObject.str(key: String): String? = runCatching { this[key]?.jsonPrimitive?.contentOrNull }.getOrNull()
}
