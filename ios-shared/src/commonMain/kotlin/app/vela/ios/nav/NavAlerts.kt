package app.vela.ios.nav

import app.vela.core.data.BridgeAlerts
import app.vela.core.model.Route
import app.vela.core.nav.CameraAlerts
import app.vela.core.nav.NavSession
import app.vela.core.nav.SpeedingAlerts
import app.vela.core.platform.Clock
import app.vela.core.util.Fmt
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A visible road alert. The banner expires on its own after six seconds. */
data class NavRoadAlert(
    val kind: NavRoadAlertKind,
    val count: Int = 1,
    val untilMs: Long = 0L,
    /** A bridge's planned opening (epoch ms), 0 for every other alert. */
    val atMs: Long = 0L,
)

/** The road-data part of NavUiState, kept separate from route guidance. */
data class NavAlertState(
    val speedLimitKmh: Double? = null,
    val speeding: Boolean = false,
    val alert: NavRoadAlert? = null,
    val loadedCameraGroups: Int = 0,
    val loadedBridges: Int = 0,
)

/** Android's speed-badge comparison, including its rounded limit and unit-specific tolerance. */
object NavSpeedDisplay {
    fun isSpeeding(speedMps: Double?, limitKmh: Double?, imperial: Boolean): Boolean {
        if (speedMps == null || limitKmh == null || limitKmh <= 0.0) return false
        val speed = if (imperial) speedMps * MPS_TO_MPH else speedMps * 3.6
        val limit = if (imperial) (limitKmh * KMH_TO_MPH).roundToInt() else limitKmh.roundToInt()
        return speed > limit + if (imperial) 3.0 else 5.0
    }

    const val MPS_TO_MPH = 2.236936
    const val KMH_TO_MPH = 0.621371
}

/**
 * Route-scoped camera loading and alert timing. A same-course route heal keeps its loaded data and
 * announced sets. A genuinely new route clears both before its fetch starts, so stale distances can
 * never announce a camera from the old route.
 */
class NavAlerts(
    private val provider: NavAlertProvider,
    private val scope: CoroutineScope,
    private val clock: Clock,
    private val imperial: () -> Boolean,
    private val audibleAlert: (NavRoadAlert) -> Unit,
    private val onChange: (NavAlertState) -> Unit,
) {
    /** Settings > Navigation > Bridge openings. A var keeps the existing constructor call sites. */
    var bridgesEnabled: () -> Boolean = { true }
    private var state = NavAlertState()
    private var routeKey: String? = null
    private var generation = 0
    private var loadJob: Job? = null
    private var expiryJob: Job? = null
    private var routeData = NavRouteData()
    private val announced = mutableMapOf<NavRoadAlertKind, Set<Int>>()
    private var announcedBridges: Set<String> = emptySet()
    private val speedingAlerts = SpeedingAlerts()
    private var lastSession: NavSession.State? = null
    private var lastSpeedMps: Double? = null

    fun onRoute(route: Route?) {
        if (route == null) {
            reset()
            return
        }
        val key = routeKey(route)
        if (key == routeKey) return
        routeKey = key
        generation++
        loadJob?.cancel()
        expiryJob?.cancel()
        routeData = NavRouteData()
        announced.clear()
        announcedBridges = emptySet()
        lastSession = null
        publish(NavAlertState())
        val gen = generation
        loadJob = scope.launch {
            val loaded = try {
                provider.load(route)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                return@launch
            }
            if (gen != generation || key != routeKey) return@launch
            routeData = loaded
            publish(state.copy(
                loadedCameraGroups = loaded.cameraGroups.size,
                loadedBridges = loaded.bridges.size,
            ))
            lastSession?.let { update(it, lastSpeedMps) }
        }
    }

    /** Applies one common-session update. Calls are cheap after the route's single fetch has landed. */
    fun update(session: NavSession.State, speedMps: Double?) {
        lastSession = session
        lastSpeedMps = speedMps
        if (!session.navigating) {
            expiryJob?.cancel()
            speedingAlerts.reset()
            publish(state.copy(speedLimitKmh = null, speeding = false, alert = null))
            return
        }
        if (session.paused) return
        val now = clock.elapsedRealtimeMillis()
        val limit = routeData.speedLimitAt(session.nav.traveledM)
        publish(state.copy(
            speedLimitKmh = limit,
            speeding = NavSpeedDisplay.isSpeeding(speedMps, limit, imperial()),
            alert = state.alert?.takeIf { it.untilMs > now },
        ))
        for (kind in listOf(NavRoadAlertKind.SPEED_CAMERA, NavRoadAlertKind.ALPR_CAMERA)) {
            val groups = routeData.cameraGroups.filter { it.kind == kind }
            if (groups.isEmpty()) continue
            val already = announced[kind].orEmpty()
            val index = CameraAlerts.due(
                groups.map { it.atMeters }, session.nav.traveledM, speedMps ?: 0.0, already,
            ) ?: continue
            announced[kind] = already + index
            trigger(NavRoadAlert(kind, groups[index].count), now)
        }
        if (speedingAlerts.update(speedMps?.times(3.6), limit, now)) {
            trigger(NavRoadAlert(NavRoadAlertKind.SPEEDING), clock.elapsedRealtimeMillis())
        }
        if (bridgesEnabled() && routeData.bridges.isNotEmpty()) {
            val due = BridgeAlerts.due(
                routeData.bridges,
                session.nav.traveledM,
                session.remainingDistance,
                session.remainingDuration,
                clock.nowMillis(),
                announcedBridges,
            )
            if (due != null) {
                val bridge = routeData.bridges[due.index]
                when (due) {
                    is BridgeAlerts.Alert.OpenNow -> {
                        announcedBridges = announcedBridges + BridgeAlerts.key(bridge, true)
                        trigger(NavRoadAlert(NavRoadAlertKind.BRIDGE_OPEN), now)
                    }
                    is BridgeAlerts.Alert.Planned -> {
                        announcedBridges = announcedBridges + BridgeAlerts.key(bridge, false)
                        trigger(NavRoadAlert(NavRoadAlertKind.BRIDGE_PLANNED, atMs = due.startMs), now)
                    }
                }
            }
        }
    }

    fun reset() {
        generation++
        routeKey = null
        loadJob?.cancel()
        expiryJob?.cancel()
        routeData = NavRouteData()
        announced.clear()
        announcedBridges = emptySet()
        speedingAlerts.reset()
        lastSession = null
        lastSpeedMps = null
        publish(NavAlertState())
    }

    private fun trigger(alert: NavRoadAlert, nowMs: Long) {
        val visible = alert.copy(untilMs = nowMs + ALERT_VISIBLE_MS)
        publish(state.copy(alert = visible))
        audibleAlert(visible)
        expiryJob?.cancel()
        expiryJob = scope.launch {
            delay(ALERT_VISIBLE_MS)
            if (state.alert == visible) publish(state.copy(alert = null))
        }
    }

    private fun publish(value: NavAlertState) {
        if (value == state) return
        state = value
        onChange(value)
    }

    private fun routeKey(route: Route): String {
        val first = route.polyline.first()
        val last = route.polyline.last()
        return Fmt.fixed(first.lat, 4) + "," + Fmt.fixed(first.lng, 4) + "|" +
            Fmt.fixed(last.lat, 4) + "," + Fmt.fixed(last.lng, 4) + "|" +
            (route.distanceMeters / 500.0).toInt()
    }

    private companion object {
        const val ALERT_VISIBLE_MS = 6_000L
    }
}
