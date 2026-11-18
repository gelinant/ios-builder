package app.vela.ios.transit

import app.vela.core.i18n.NavStrings
import app.vela.core.i18n.NavStringsRegistry
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.bearingTo
import app.vela.core.model.distanceTo
import app.vela.core.nav.RouteProjection
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt

/** The kind of move one walking instruction asks for. Derived from the leg's own geometry when the
 *  planner supplied no street-level steps; kept separate from [ManeuverType] because a walk has no
 *  ramps, lanes or roundabout exits. */
enum class WalkManeuver {
    START, LEFT, RIGHT, SLIGHT_LEFT, SLIGHT_RIGHT, SHARP_LEFT, SHARP_RIGHT, UTURN, CONTINUE, ARRIVE,
}

/**
 * One instruction of a walking leg. [atMeters] is where the move happens along the leg, and
 * [distanceMeters] is the walk after it to the next instruction. [road] is present only when the
 * walk router named the street; a plan built from bare geometry leaves it null rather than
 * inventing a name.
 */
data class WalkInstruction(
    val maneuver: WalkManeuver,
    val atMeters: Double,
    val distanceMeters: Double,
    val road: String?,
    val text: String,
    val spoken: String,
)

/**
 * A walking leg's ordered instructions and the path they follow. [source] is `steps` when the walk
 * router answered with named maneuvers, `path` when only the leg's geometry was available (the
 * usual Transitous case), and `straight` when not even a path was present and only the two ends
 * were known. The UI reports that difference instead of pretending the streets are known.
 */
data class WalkPlan(
    val instructions: List<WalkInstruction>,
    val path: List<LatLng>,
    val totalMeters: Double,
    val source: String,
    val targetName: String?,
) {
    val named: Boolean get() = instructions.any { it.road != null }
}

/** The current walking guidance published to Swift. [prompt] is set only on the emission that
 *  should speak; [promptSeq] lets Swift speak each prompt exactly once, in order. */
data class TransitWalkState(
    val active: Boolean = false,
    val source: String = "",
    val named: Boolean = false,
    val instruction: String = "",
    val distanceMeters: Double = -1.0,
    val remainingMeters: Double = -1.0,
    val instructionIndex: Int = 0,
    val instructionCount: Int = 0,
    val targetName: String = "",
    val prompt: String? = null,
    val promptSeq: Int = 0,
)

/**
 * Builds walking instructions from a leg. A Transitous walk carries its own path but no
 * street-level steps, so the default plan is derived from bearings: the path is simplified, each
 * significant bearing change becomes a left or right turn, and the text says the direction
 * without a street name. When the walk router does answer with maneuvers, those named steps and
 * their roads are used as they are. No instruction is invented for a leg with no geometry.
 */
object WalkingDirections {
    /** How far a point may sit from the simplified line before it is kept as a corner. */
    private const val SIMPLIFY_M = 10.0
    /** A bearing change below this is the same street curving, not a turn to announce. */
    private const val TURN_MIN_DEG = 20.0
    private const val SLIGHT_MAX_DEG = 45.0
    private const val SHARP_MIN_DEG = 135.0

    /**
     * The geometry plan. [path] may be null; the two endpoints then give a straight instruction
     * and [WalkPlan.source] says `straight`. Null when neither a path nor both endpoints exist.
     */
    fun fromGeometry(
        path: List<LatLng>?,
        from: LatLng?,
        to: LatLng?,
        targetName: String?,
        strings: NavStrings = NavStringsRegistry.current(),
    ): WalkPlan? {
        val valid = path.orEmpty().filter { it.lat in -90.0..90.0 && it.lng in -180.0..180.0 }
        val points = when {
            valid.size >= 2 -> valid
            from != null && to != null && from != to -> listOf(from, to)
            else -> return null
        }
        val source = if (valid.size >= 2) "path" else "straight"
        val cum = RouteProjection.cumulative(points)
        val total = cum.lastOrNull() ?: 0.0
        val corners = simplify(points, SIMPLIFY_M)
        val turns = ArrayList<Pair<LatLng, WalkManeuver>>()
        for (i in 1 until corners.size - 1) {
            val a = corners[i - 1]
            val b = corners[i]
            val c = corners[i + 1]
            val incoming = a.bearingTo(b)
            val outgoing = b.bearingTo(c)
            val delta = signedDelta(incoming, outgoing)
            val maneuver = classify(delta) ?: continue
            turns += b to maneuver
        }
        val atOf = cornerDistances(points, corners)
        val starts = listOf(0.0) + turns.map { atOf[it.first] ?: 0.0 }
        val instructions = ArrayList<WalkInstruction>()
        instructions += WalkInstruction(
            maneuver = WalkManeuver.START,
            atMeters = 0.0,
            distanceMeters = 0.0,
            road = null,
            text = strings.phrase("depart", null, null, null, null, null),
            spoken = strings.phrase("depart", null, null, null, null, null),
        )
        turns.forEachIndexed { index, (_, maneuver) ->
            val text = textFor(maneuver, null, strings)
            instructions += WalkInstruction(
                maneuver = maneuver,
                atMeters = starts[index + 1],
                distanceMeters = 0.0,
                road = null,
                text = text,
                spoken = text,
            )
        }
        instructions += WalkInstruction(
            maneuver = WalkManeuver.ARRIVE,
            atMeters = total,
            distanceMeters = 0.0,
            road = null,
            text = strings.phrase("arrive", null, null, null, null, null),
            spoken = strings.phrase("arrive", null, null, null, null, null),
        )
        return WalkPlan(
            instructions = withDistances(instructions, total),
            path = points,
            totalMeters = total,
            source = source,
            targetName = targetName?.takeIf { it.isNotBlank() },
        )
    }

    /**
     * The router plan: its own ordered maneuvers, with the streets they name. [path] is the leg's
     * geometry when it exists, so progress can still be projected along the ground. Maneuvers with
     * no usable text are skipped rather than shown empty.
     */
    fun fromManeuvers(
        maneuvers: List<Maneuver>,
        path: List<LatLng>?,
        targetName: String?,
    ): WalkPlan? {
        if (maneuvers.isEmpty()) return null
        val valid = path.orEmpty().filter { it.lat in -90.0..90.0 && it.lng in -180.0..180.0 }
        val points = if (valid.size >= 2) valid else maneuvers.map { it.location }
        if (points.size < 2) return null
        val total = RouteProjection.cumulative(points).lastOrNull() ?: 0.0
        var at = 0.0
        val all = ArrayList<WalkInstruction>()
        for (maneuver in maneuvers) {
            val text = maneuver.instruction.takeIf { it.isNotBlank() } ?: continue
            all += WalkInstruction(
                maneuver = maneuver.walkKind(),
                atMeters = at,
                distanceMeters = 0.0,
                road = maneuver.road?.takeIf { it.isNotBlank() },
                text = text,
                spoken = maneuver.spokenInstruction(),
            )
            at += maneuver.distanceMeters.coerceAtLeast(0.0)
        }
        if (all.isEmpty()) return null
        if (all.none { it.maneuver == WalkManeuver.ARRIVE }) {
            all += WalkInstruction(
                maneuver = WalkManeuver.ARRIVE,
                atMeters = total,
                distanceMeters = 0.0,
                road = null,
                text = NavStringsRegistry.current().phrase("arrive", null, null, null, null, null),
                spoken = NavStringsRegistry.current().phrase("arrive", null, null, null, null, null),
            )
        }
        val clamped = all.map { it.copy(atMeters = it.atMeters.coerceIn(0.0, total)) }
            .sortedBy { it.atMeters }
        return WalkPlan(
            instructions = withDistances(clamped, total),
            path = points,
            totalMeters = total,
            source = "steps",
            targetName = targetName?.takeIf { it.isNotBlank() },
        )
    }

    private fun withDistances(instructions: List<WalkInstruction>, total: Double): List<WalkInstruction> =
        instructions.mapIndexed { index, instruction ->
            val next = instructions.getOrNull(index + 1)?.atMeters ?: total
            instruction.copy(distanceMeters = (next - instruction.atMeters).coerceAtLeast(0.0))
        }

    private fun textFor(maneuver: WalkManeuver, road: String?, strings: NavStrings): String =
        when (maneuver) {
            WalkManeuver.START -> strings.phrase("depart", null, road, null, null, null)
            WalkManeuver.LEFT -> strings.phrase("turn", "left", road, null, null, null)
            WalkManeuver.RIGHT -> strings.phrase("turn", "right", road, null, null, null)
            WalkManeuver.SLIGHT_LEFT -> strings.phrase("turn", "slight left", road, null, null, null)
            WalkManeuver.SLIGHT_RIGHT -> strings.phrase("turn", "slight right", road, null, null, null)
            WalkManeuver.SHARP_LEFT -> strings.phrase("turn", "sharp left", road, null, null, null)
            WalkManeuver.SHARP_RIGHT -> strings.phrase("turn", "sharp right", road, null, null, null)
            WalkManeuver.UTURN -> strings.phrase("uturn", null, road, null, null, null)
            WalkManeuver.CONTINUE -> strings.phrase("continue", "straight", road, null, null, null)
            WalkManeuver.ARRIVE -> strings.phrase("arrive", null, road, null, null, null)
        }

    private fun Maneuver.walkKind(): WalkManeuver = when (type) {
        ManeuverType.DEPART -> WalkManeuver.START
        ManeuverType.ARRIVE -> WalkManeuver.ARRIVE
        ManeuverType.TURN_LEFT -> WalkManeuver.LEFT
        ManeuverType.TURN_RIGHT -> WalkManeuver.RIGHT
        ManeuverType.SLIGHT_LEFT, ManeuverType.KEEP_LEFT, ManeuverType.FORK_LEFT -> WalkManeuver.SLIGHT_LEFT
        ManeuverType.SLIGHT_RIGHT, ManeuverType.KEEP_RIGHT, ManeuverType.FORK_RIGHT -> WalkManeuver.SLIGHT_RIGHT
        ManeuverType.SHARP_LEFT -> WalkManeuver.SHARP_LEFT
        ManeuverType.SHARP_RIGHT -> WalkManeuver.SHARP_RIGHT
        ManeuverType.UTURN -> WalkManeuver.UTURN
        else -> WalkManeuver.CONTINUE
    }

    private fun classify(delta: Double): WalkManeuver? {
        val magnitude = abs(delta)
        if (magnitude < TURN_MIN_DEG) return null
        return when {
            magnitude >= SHARP_MIN_DEG && magnitude > 160.0 -> WalkManeuver.UTURN
            magnitude >= SHARP_MIN_DEG -> if (delta < 0) WalkManeuver.SHARP_LEFT else WalkManeuver.SHARP_RIGHT
            magnitude >= SLIGHT_MAX_DEG -> if (delta < 0) WalkManeuver.LEFT else WalkManeuver.RIGHT
            else -> if (delta < 0) WalkManeuver.SLIGHT_LEFT else WalkManeuver.SLIGHT_RIGHT
        }
    }

    /** Signed bearing change, positive to the right, in (-180, 180]. */
    internal fun signedDelta(fromDeg: Double, toDeg: Double): Double {
        var d = (toDeg - fromDeg) % 360.0
        if (d > 180.0) d -= 360.0
        if (d <= -180.0) d += 360.0
        return d
    }

    /** Ramer-Douglas-Peucker, with the deviation measured in meters in a local flat frame. */
    private fun simplify(points: List<LatLng>, tolerance: Double): List<LatLng> {
        if (points.size <= 2) return points
        val keep = BooleanArray(points.size)
        keep[0] = true
        keep[points.size - 1] = true
        simplifyInto(points, 0, points.size - 1, tolerance, keep)
        val out = points.filterIndexed { index, _ -> keep[index] }
        // Fold points that are still almost on top of each other: their bearing is noise.
        val cleaned = ArrayList<LatLng>()
        for (p in out) {
            if (cleaned.isEmpty() || cleaned.last().distanceTo(p) >= 2.0) cleaned += p
        }
        if (cleaned.size == 1) cleaned += points.last()
        return cleaned
    }

    private fun simplifyInto(points: List<LatLng>, first: Int, last: Int, tolerance: Double, keep: BooleanArray) {
        if (last <= first + 1) return
        var worst = 0.0
        var index = first
        for (i in first + 1 until last) {
            val d = distanceToSegmentMeters(points[i], points[first], points[last])
            if (d > worst) {
                worst = d
                index = i
            }
        }
        if (worst > tolerance) {
            keep[index] = true
            simplifyInto(points, first, index, tolerance, keep)
            simplifyInto(points, index, last, tolerance, keep)
        }
    }

    private fun distanceToSegmentMeters(p: LatLng, a: LatLng, b: LatLng): Double {
        val latScale = cos(p.lat * kotlin.math.PI / 180.0)
        val bx = (b.lng - a.lng) * latScale
        val by = b.lat - a.lat
        val px = (p.lng - a.lng) * latScale
        val py = p.lat - a.lat
        val len2 = bx * bx + by * by
        val t = if (len2 <= 0.0) 0.0 else (((px * bx) + (py * by)) / len2).coerceIn(0.0, 1.0)
        return hypot(px - bx * t, py - by * t) * 111_320.0
    }

    private fun cornerDistances(points: List<LatLng>, corners: List<LatLng>): Map<LatLng, Double> {
        val cum = RouteProjection.cumulative(points)
        val out = HashMap<LatLng, Double>()
        var j = 0
        for (i in points.indices) {
            if (j < corners.size && points[i] == corners[j]) {
                out[corners[j]] = cum[i]
                j += 1
            }
        }
        return out
    }
}

/**
 * Progress through one [WalkPlan]. Prompts are spoken once per band: the far call ("In 40 meters,
 * turn right") and the near call at the turn. A poor fix never reaches this class: TransitSession
 * rejects an accuracy over its limit before projecting it, and a fix off the line keeps the last
 * along-distance rather than teleporting the walker.
 */
class WalkGuide(
    val plan: WalkPlan,
    private val strings: NavStrings,
    private val imperial: Boolean,
) {
    private val cumulative = RouteProjection.cumulative(plan.path)
    private val said = HashSet<String>()

    /** How far along the plan [fix] sits, or null when it is not near the walking line. */
    fun alongOf(fix: LatLng): Double? =
        RouteProjection.alongMeters(plan.path, cumulative, fix, maxOffRouteM = MAX_OFF_ROUTE_M)

    /** The banner state at [alongMeters]. The upcoming move is shown until its own point is
     *  reached, so the card answers "what do I do next" between turns. */
    fun view(alongMeters: Double): TransitWalkState {
        val along = alongMeters.coerceIn(0.0, plan.totalMeters)
        val first = plan.instructions.firstOrNull() ?: return TransitWalkState()
        val upcomingIndex = plan.instructions.indexOfFirst { it.atMeters > along + AT_POINT_M }
        val displayIndex = when {
            along < START_SHOWN_M && first.maneuver == WalkManeuver.START -> 0
            upcomingIndex >= 0 -> upcomingIndex
            else -> plan.instructions.lastIndex
        }
        val display = plan.instructions[displayIndex]
        val distance = when {
            display.maneuver == WalkManeuver.ARRIVE -> plan.totalMeters - along
            displayIndex == 0 -> 0.0
            else -> (display.atMeters - along).coerceAtLeast(0.0)
        }
        return TransitWalkState(
            active = true,
            source = plan.source,
            named = plan.named,
            instruction = display.text,
            distanceMeters = distance,
            remainingMeters = (plan.totalMeters - along).coerceAtLeast(0.0),
            instructionIndex = displayIndex,
            instructionCount = plan.instructions.size,
            targetName = plan.targetName.orEmpty(),
        )
    }

    /** The prompt to speak now, or null. Each band is said once for its instruction. */
    fun takePrompt(alongMeters: Double): String? {
        val along = alongMeters.coerceIn(0.0, plan.totalMeters)
        val first = plan.instructions.firstOrNull() ?: return null
        if (along < START_SHOWN_M && first.maneuver == WalkManeuver.START && said.add("start")) {
            return first.spoken
        }
        val index = plan.instructions.indexOfFirst { it.atMeters > along + AT_POINT_M }
        val upcoming = plan.instructions.getOrNull(index) ?: return null
        val distance = if (upcoming.maneuver == WalkManeuver.ARRIVE) {
            plan.totalMeters - along
        } else {
            (upcoming.atMeters - along).coerceAtLeast(0.0)
        }
        if (upcoming.maneuver == WalkManeuver.ARRIVE) {
            return when {
                distance <= ARRIVE_NEAR_M && said.add("arrive") -> strings.arrived()
                distance <= ARRIVE_FAR_M && said.add("arrive:far") ->
                    strings.inThen(strings.spokenDistance(roundDistance(distance), imperial), upcoming.spoken)
                else -> null
            }
        }
        return when {
            distance <= NEAR_M && said.add("$index:near") -> upcoming.spoken
            distance <= FAR_M && said.add("$index:far") ->
                strings.inThen(strings.spokenDistance(roundDistance(distance), imperial), upcoming.spoken)
            else -> null
        }
    }

    /** Mark the arrival callout as said, so a final fix and the leg change cannot repeat it. */
    fun markArrived() {
        said.add("arrive")
    }

    private fun roundDistance(meters: Double): Double =
        (meters / 10.0).roundToInt().coerceAtLeast(1) * 10.0

    companion object {
        const val NEAR_M = 12.0
        const val FAR_M = 45.0
        const val ARRIVE_NEAR_M = 12.0
        const val ARRIVE_FAR_M = 35.0
        const val AT_POINT_M = 3.0
        const val START_SHOWN_M = 8.0
        const val MAX_OFF_ROUTE_M = 80.0
    }
}
