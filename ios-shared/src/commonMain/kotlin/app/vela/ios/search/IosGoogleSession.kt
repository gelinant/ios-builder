package app.vela.ios.search

import app.vela.core.config.Calibration
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.ios.net.BrowserIdentity
import kotlin.concurrent.Volatile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Cookie warming, as Android's `GoogleSession`: one GET of the Maps home page before the first
 * data call, so the client's cookie jar (pre-seeded with SOCS and CONSENT by the Swift
 * `VelaHttp`) picks up Google's own cookies. A failed warm-up is not retried: the search goes on
 * without it, as on Android. A cancelled one is, on the next call.
 */
class IosGoogleSession(
    private val http: VelaHttp,
    private val calibration: () -> Calibration,
    private val identity: BrowserIdentity,
    private val acceptLanguage: () -> String,
) {
    @Volatile
    private var warmed = false
    private val mutex = Mutex()

    suspend fun ensure() {
        if (warmed) return
        mutex.withLock {
            if (warmed) return
            try {
                val url = calibration().sessionWarmUrl
                http.call(HttpRequest(url = url, headers = identity.documentHeaders(acceptLanguage())))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            }
            warmed = true
        }
    }

    fun invalidate() {
        warmed = false
    }
}
