package app.vela.ios.config

import app.vela.core.config.Calibration
import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.platform.Cancellable
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.JsEngine
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.i
import app.vela.core.platform.w
import kotlin.concurrent.Volatile
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * The live calibration on iOS, as Android's `MapViewModel` init runs it: the common
 * [CalibrationStore] (cached signed copy or [Calibration.DEFAULT] at once, then one refresh from
 * the same URLs and in the same fallback order) and the [JsTransforms] over it.
 *
 * Building it does nothing (docs/ios/PRESENTATION-MAP.md, trap 1); [start] reads the cache and
 * launches the refresh on [scope]. Before [start], [current] is [Calibration.DEFAULT] and
 * [transforms] is null.
 */
class IosCalibration(
    private val core: CoreGraph,
    private val signatures: SignatureVerifier,
    private val js: JsEngine,
    private val scope: CoroutineScope,
) {
    @Volatile
    private var store: CalibrationStore? = null

    @Volatile
    var transforms: JsTransforms? = null
        private set

    private val _version = MutableStateFlow(0)

    /** The active bundle's version: 0 before [start], then the cached or compiled one, then the
     *  refreshed one. */
    val version: StateFlow<Int> = _version.asStateFlow()

    private val _refreshed = MutableStateFlow(false)

    /** True once the startup refresh has finished, adopted or not. */
    val refreshed: StateFlow<Boolean> = _refreshed.asStateFlow()

    fun current(): Calibration = store?.current() ?: Calibration.DEFAULT

    fun start() {
        if (store != null) return
        val s = CalibrationStore(core, signatures)
        store = s
        transforms = JsTransforms(s, js)
        _version.value = s.current().version
        core.log.i(TAG, "calibration at startup: version ${s.current().version}")
        scope.launch {
            try {
                s.refresh()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                core.log.w(TAG, "calibration refresh failed", e)
            }
            val now = s.current().version
            _version.value = now
            core.log.i(TAG, "calibration after refresh: version $now")
            _refreshed.value = true
        }
    }

    /** Calls [onChange] with [version] now and on each change, on the scope's thread, until the
     *  handle is cancelled. For Swift code that cannot iterate [version] through SKIE. */
    fun watchVersion(onChange: (Int) -> Unit): Cancellable {
        val job = scope.launch { version.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    companion object {
        const val TAG = "Calibration"
    }
}
