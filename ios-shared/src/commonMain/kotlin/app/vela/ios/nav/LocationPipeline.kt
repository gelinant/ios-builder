package app.vela.ios.nav

import app.vela.core.location.FixRules
import app.vela.core.model.LatLng
import app.vela.core.model.bearingTo
import app.vela.core.model.distanceTo
import app.vela.core.platform.Clock
import kotlin.math.abs
import kotlin.math.max
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** One platform fix. [elapsedNanos] comes from the monotonic clock at delivery, never
 * `CLLocation.timestamp`. iOS has no provider name: every Core Location update is passed with
 * [gnss] true, so accuracy is the only discriminator, and only 50 m or better reaches guidance. */
data class LocationFix(
    val latitude: Double,
    val longitude: Double,
    val accuracyM: Double?,
    val speedMps: Double?,
    val bearingDeg: Double?,
    val elapsedNanos: Long,
    val gnss: Boolean = true,
)

/** The filtered position and motion shown by the map and used by the drive camera. */
data class LocationState(
    val latitude: Double? = null,
    val longitude: Double? = null,
    val accuracyM: Double? = null,
    val speedMps: Double? = null,
    val bearingDeg: Double? = null,
    val stale: Boolean = false,
    val starved: Boolean = false,
    val fixSequence: Long = 0,
)

/** A fix that is accurate enough to steer the navigation engine. */
data class GuidanceFix(
    val position: LatLng,
    val speedMps: Double?,
    val accuracyM: Double?,
    val bearingDeg: Double?,
)

/**
 * The iOS counterpart of `MapViewModel.startLocation`: monotonic ordering, outlier and speed
 * gates, speed-adaptive smoothing, a fresh-course rule, and a separate guidance-quality feed.
 * Building it is inert; [start] arms the stale timers. Calls arrive on the main thread on iOS.
 */
class LocationPipeline(
    private val scope: CoroutineScope,
    private val clock: Clock,
    private val onState: (LocationState) -> Unit = {},
    private val onGuidance: (GuidanceFix) -> Unit = {},
) {
    private val _state = MutableStateFlow(LocationState())
    val state: StateFlow<LocationState> = _state.asStateFlow()

    private var timer: Job? = null
    private var navigating = false
    private var lastFixNanos = 0L
    private var lastFixMs = 0L
    private var lastGpsMs = 0L
    private var lastGuidanceMs = 0L
    private var lastSpeedEvidenceMs = 0L
    private var lastAccuracy: Float? = null
    private var lastAccuracyNanos = 0L
    private var previousWasGps = false
    private var outlierStreak = 0
    private var speedGateBase: Float? = null
    private var speedGateStreak = 0
    private var sequence = 0L

    fun start() {
        if (timer != null) return
        timer = scope.launch {
            while (isActive) {
                delay(1_000)
                val now = clock.elapsedRealtimeMillis()
                val stale = lastFixMs > 0L && now - lastFixMs >= STALE_LOCATION_MS
                val starved = navigating && now - lastGuidanceMs >= NAV_STARVED_MS
                val speed = if (lastFixMs > 0L && now - lastFixMs >= SPEED_ZERO_MS) 0.0 else _state.value.speedMps
                if (stale != _state.value.stale || starved != _state.value.starved || speed != _state.value.speedMps) {
                    publish(_state.value.copy(stale = stale, starved = starved, speedMps = speed))
                }
            }
        }
    }

    /** Starts the starvation window with the drive, before its first guidance-quality fix. */
    fun navigationStarted() {
        navigating = true
        lastGuidanceMs = clock.elapsedRealtimeMillis()
        publish(_state.value.copy(starved = false))
    }

    fun navigationEnded() {
        navigating = false
        publish(_state.value.copy(starved = false))
    }

    fun onFix(fix: LocationFix) {
        if (fix.latitude !in -90.0..90.0 || fix.longitude !in -180.0..180.0) return
        if (lastFixNanos > 0L && fix.elapsedNanos <= lastFixNanos) return
        val nowMs = clock.elapsedRealtimeMillis()
        if (!fix.gnss && lastGpsMs > 0L && nowMs - lastGpsMs < NETWORK_FIX_QUIET_MS) return
        if (fix.gnss) lastGpsMs = nowMs

        val raw = LatLng(fix.latitude, fix.longitude)
        val previous = _state.value.let { s ->
            if (s.latitude != null && s.longitude != null) LatLng(s.latitude, s.longitude) else null
        }
        val dt = if (lastFixNanos > 0L) (fix.elapsedNanos - lastFixNanos) / 1e9 else -1.0
        val accuracy = (fix.accuracyM?.takeIf { it >= 0.0 } ?: if (fix.gnss) 10.0 else 1_000.0).toFloat()
        if (!fix.gnss && lastAccuracy != null) {
            val age = (fix.elapsedNanos - lastAccuracyNanos) / 1e9
            val speed = ((_state.value.speedMps ?: 0.0) + (fix.speedMps?.takeIf { it >= 0.0 } ?: 0.0)) / 2.0
            if (!FixRules.betterThanLast(accuracy, lastAccuracy!!, age, speed)) return
        }
        val upgrade = FixRules.isUpgrade(
            lastAccuracy, accuracy, previousWasGps, fix.gnss, previous?.distanceTo(raw) ?: 0.0,
        )
        val here = if (upgrade) {
            outlierStreak = 0
            raw
        } else {
            sanePosition(raw, previous, _state.value.speedMps, dt)
        }
        val moved = previous?.distanceTo(here) ?: 0.0
        val accuracyFloor = max(3.0, accuracy.toDouble() * 0.7)
        val canDerive = previous != null && previousWasGps && fix.gnss && moved > accuracyFloor && dt in 0.3..10.0
        val wide = accuracy > ACC_TRUST_M
        val slow = SLOW_MPS
        val measuredBearing = fix.bearingDeg?.takeIf { it.isFinite() && it >= 0.0 }
        val measuredSpeed = fix.speedMps?.takeIf { it.isFinite() && it >= 0.0 }
        val freshBearing = when {
            measuredBearing != null && (measuredSpeed ?: 0.0) > 0.5 && (!wide || (measuredSpeed ?: 0.0) >= slow) -> measuredBearing
            canDerive && moved > 3.0 && (!wide || moved / dt >= slow) -> previous.bearingTo(here)
            else -> null
        }
        val bearing = freshBearing ?: _state.value.bearingDeg
        val hasEvidence = measuredSpeed != null || canDerive
        if (hasEvidence) lastSpeedEvidenceMs = nowMs
        val rawSpeed = when {
            measuredSpeed != null -> measuredSpeed
            canDerive -> (moved / dt).coerceIn(0.0, 70.0)
            nowMs - lastSpeedEvidenceMs > SPEED_HOLD_MS -> 0.0
            else -> _state.value.speedMps
        }?.let { if (it < slow && wide) 0.0 else it }
        val gated = if (hasEvidence && rawSpeed != null) gateSpeed(rawSpeed, dt) else null
        val speed = when {
            gated != null -> gated
            hasEvidence -> _state.value.speedMps
            else -> rawSpeed
        }

        lastFixNanos = fix.elapsedNanos
        lastFixMs = nowMs
        lastAccuracy = accuracy
        lastAccuracyNanos = fix.elapsedNanos
        previousWasGps = fix.gnss
        sequence++
        publish(LocationState(
            latitude = here.lat,
            longitude = here.lng,
            accuracyM = accuracy.toDouble(),
            speedMps = speed,
            bearingDeg = bearing,
            stale = false,
            starved = navigating && nowMs - lastGuidanceMs >= NAV_STARVED_MS,
            fixSequence = sequence,
        ))

        if (fix.gnss && accuracy <= GUIDANCE_ACCURACY_M) {
            lastGuidanceMs = nowMs
            onGuidance(GuidanceFix(here, speed, accuracy.toDouble(), freshBearing))
            if (_state.value.starved) publish(_state.value.copy(starved = false))
        } else if (navigating && nowMs - lastGuidanceMs >= NAV_STARVED_MS && !_state.value.starved) {
            publish(_state.value.copy(starved = true))
        }
    }

    /** Port of `sanePosition`: cap one-fix leaps, accept a persistent new reality after three,
     * and ease from heavy smoothing at rest to one-to-one tracking at 10 m/s. */
    private fun sanePosition(raw: LatLng, previous: LatLng?, speed: Double?, dt: Double): LatLng {
        if (previous == null || dt < 0.0) {
            outlierStreak = 0
            return raw
        }
        val plausible = ((speed ?: 0.0) + 12.0) * dt + 35.0
        if (previous.distanceTo(raw) > plausible) {
            if (outlierStreak >= 2) {
                outlierStreak = 0
                return raw
            }
            outlierStreak++
            return previous
        }
        outlierStreak = 0
        val k = ((speed ?: 0.0) / 10.0).coerceIn(0.12, 1.0)
        return LatLng(previous.lat + (raw.lat - previous.lat) * k, previous.lng + (raw.lng - previous.lng) * k)
    }

    /** Port of `gateMeasuredSpeed`: acceleration-bounded in both directions, self-healing on the
     * second consecutive out-of-band measurement. */
    private fun gateSpeed(raw: Double, dt: Double): Double? {
        val base = speedGateBase
        val bound = 8.0 * dt.coerceIn(0.5, 3.0) + 5.0
        return if (base != null && dt > 0.0 && dt <= 3.0 && abs(raw - base) > bound && speedGateStreak == 0) {
            speedGateStreak = 1
            null
        } else {
            speedGateStreak = 0
            speedGateBase = raw.toFloat()
            raw
        }
    }

    private fun publish(value: LocationState) {
        _state.value = value
        onState(value)
    }

    companion object {
        const val GUIDANCE_ACCURACY_M = 50.0
        private const val NETWORK_FIX_QUIET_MS = 12_000L
        private const val SPEED_HOLD_MS = 3_000L
        private const val SPEED_ZERO_MS = 6_000L
        private const val STALE_LOCATION_MS = 12_000L
        private const val NAV_STARVED_MS = 10_000L
        private const val ACC_TRUST_M = 30.0
        private const val SLOW_MPS = 3.0
    }
}
