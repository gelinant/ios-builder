package app.vela.ios.world

import app.vela.core.platform.VelaHttp
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Clock

/** What one maritime refresh produced. [rows] is what the sheet shows, [ships] what the map
 *  draws. [coverage] and [aishub] are stable markers for tests and for the next lot. */
data class MaritimeSnapshot(
    val updatedAtMs: Long,
    val rows: List<MaritimeRow>,
    val ships: List<AisShip>,
    val coverage: String,
    val aishub: String,
)

/**
 * Ships around the view from Digitraffic and, only with a member key, AISHub.
 *
 * A refresh makes at most one Digitraffic request and one AISHub request. The merged answer is
 * cached for five minutes while the view stays inside the fetched box, so AISHub is called at
 * most once per five minutes, under its one-per-minute limit. Positions are deduplicated by
 * MMSI, the fresher one wins, and the 500 ships nearest the view center are kept. A source that
 * fails never erases the previous rows; a source without a key says so in a row instead of
 * showing an empty sea.
 */
class MaritimeStore internal constructor(
    private val digitraffic: AisSource,
    private val aishub: AisSource,
    private val now: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) {
    constructor(http: VelaHttp) : this(DigitrafficSource(http), AishubSource(http))

    private var cached: MaritimeSnapshot? = null
    private var cachedAtMs = 0L
    private var cachedBox: MaritimeBox? = null
    private var cachedKeyHash: Int? = null
    private var cachedFinland = false

    suspend fun refresh(box: MaritimeBox, aishubKey: String?): MaritimeSnapshot? {
        if (!box.isValid) return cached
        val key = aishubKey?.trim()?.takeIf { it.isNotEmpty() }
        val keyHash = key?.hashCode()
        val nowMs = now()
        val current = cached
        if (current != null && cachedKeyHash == keyHash && nowMs - cachedAtMs in 0 until CACHE_MS &&
            cachedFinland == box.intersectsFinland() &&
            cachedBox?.contains(box.centerLat, box.centerLng) == true) {
            return current
        }

        val digitrafficAnswer = ask(digitraffic, box, null)
        val aishubAnswer = if (key == null) {
            AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED)
        } else {
            ask(aishub, box, key)
        }

        val digitrafficShips = (digitrafficAnswer as? AisAnswer.Ships)?.list.orEmpty()
        val aishubShips = (aishubAnswer as? AisAnswer.Ships)?.list.orEmpty()
        val outside = digitrafficAnswer is AisAnswer.OutsideCoverage
        val anyData = digitrafficAnswer is AisAnswer.Ships || aishubAnswer is AisAnswer.Ships
        val rejectionOnly = aishubAnswer is AisAnswer.KeyRejected && !anyData

        // Both feeds failed and there is no explicit rejection to report. Keep what the sheet
        // already had; with no earlier data the host says "unavailable" rather than "no ships".
        if (!anyData && !rejectionOnly && !outside) {
            return current?.takeIf {
                cachedBox?.contains(box.centerLat, box.centerLng) == true
            }
        }

        val merged = LinkedHashMap<String, AisShip>()
        for (ship in digitrafficShips + aishubShips) {
            val previous = merged[ship.mmsi]
            if (previous == null || ship.updatedAtMs > previous.updatedAtMs) merged[ship.mmsi] = ship
        }
        val ordered = merged.values.sortedWith(
            compareBy<AisShip> { it.distanceM(box.centerLat, box.centerLng) }
                .thenBy { it.mmsi })
        val ships = ordered.take(MAX_SHIPS)

        val coverage = when {
            outside && aishubShips.isNotEmpty() -> COVERAGE_AISHUB_ONLY
            outside -> COVERAGE_OUTSIDE
            digitrafficAnswer is AisAnswer.Failed && aishubShips.isNotEmpty() ->
                COVERAGE_AISHUB_ONLY
            digitrafficAnswer is AisAnswer.Failed && !anyData -> COVERAGE_NONE
            aishubShips.isNotEmpty() -> COVERAGE_BOTH
            else -> COVERAGE_FINLAND
        }
        val aishubState = when (aishubAnswer) {
            is AisAnswer.Ships -> AISHUB_OK
            is AisAnswer.KeyRequired -> AISHUB_KEY_REQUIRED
            is AisAnswer.KeyRejected -> AISHUB_REJECTED
            AisAnswer.Failed -> AISHUB_FAILED
            AisAnswer.OutsideCoverage -> AISHUB_FAILED
        }
        val newest = ships.maxOfOrNull { it.updatedAtMs }?.takeIf { it > 0L } ?: nowMs

        val rows = ArrayList<MaritimeRow>(ships.size + 4)
        rows += MaritimeRow("maritime-coverage", coverageTitle(coverage), coverageDetail(coverage))
        rows += aishubRow(aishubAnswer, key != null, aishubShips.size)
        if (ships.isEmpty()) rows += emptyRow(coverage)
        for (ship in ships) {
            rows += MaritimeRow(
                id = "maritime-ship-${ship.mmsi}",
                title = ship.title,
                detail = ship.detail,
                lat = ship.lat,
                lng = ship.lng)
        }

        val snapshot = MaritimeSnapshot(
            updatedAtMs = newest,
            rows = rows,
            ships = ships,
            coverage = coverage,
            aishub = aishubState)
        cached = snapshot
        cachedAtMs = nowMs
        cachedBox = box
        cachedKeyHash = keyHash
        cachedFinland = box.intersectsFinland()
        return snapshot
    }

    companion object {
        const val MAX_SHIPS = 500
        const val CACHE_MS = 5L * 60L * 1_000L

        const val COVERAGE_FINLAND = "finland_only"
        const val COVERAGE_BOTH = "digitraffic_and_aishub"
        const val COVERAGE_AISHUB_ONLY = "aishub_only"
        const val COVERAGE_OUTSIDE = "outside_finland"
        const val COVERAGE_NONE = "none"

        const val AISHUB_OK = "ok"
        const val AISHUB_KEY_REQUIRED = "key_required"
        const val AISHUB_REJECTED = "rejected"
        const val AISHUB_FAILED = "failed"
    }

    private suspend fun ask(source: AisSource, box: MaritimeBox, key: String?): AisAnswer = try {
        source.fetch(box, key)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        AisAnswer.Failed
    }

    private fun coverageTitle(coverage: String): String = when (coverage) {
        COVERAGE_BOTH -> "AIS coverage: Digitraffic and AISHub"
        COVERAGE_AISHUB_ONLY -> "AIS coverage: AISHub member feed"
        COVERAGE_OUTSIDE -> "AIS coverage: Finland only"
        COVERAGE_NONE -> "AIS coverage: no source answered"
        else -> "AIS coverage: Finland only"
    }

    private fun coverageDetail(coverage: String): String = when (coverage) {
        COVERAGE_BOTH ->
            "Finland from Digitraffic, the rest from AISHub with a member key. " +
                "Not for navigation."
        COVERAGE_AISHUB_ONLY ->
            "Digitraffic did not answer, or this view is outside Finland; the member feed is " +
                "shown. Not for navigation."
        COVERAGE_OUTSIDE ->
            "Digitraffic covers Finnish waters only and no AISHub key is saved. " +
                "Not for navigation."
        COVERAGE_NONE ->
            "Neither Digitraffic nor AISHub answered. Nothing is invented. Not for navigation."
        else ->
            "Digitraffic covers Finnish waters only. Beyond Finland an AISHub member key is " +
                "needed. Not for navigation."
    }

    private fun aishubRow(answer: AisAnswer, keyed: Boolean, count: Int): MaritimeRow =
        when (answer) {
            is AisAnswer.Ships -> MaritimeRow(
                id = "maritime-aishub",
                title = if (count == 0) {
                    "AISHub: member key, no ship in view"
                } else {
                    "AISHub: member key, $count ships"
                },
                detail = "At most one request per minute. Data: AISHub contributors. " +
                    "Not for navigation.")
            is AisAnswer.KeyRejected -> MaritimeRow(
                id = "maritime-aishub",
                title = "AISHub: key rejected",
                detail = "${answer.message} Digitraffic remains Finland only.")
            AisAnswer.Failed -> MaritimeRow(
                id = "maritime-aishub",
                title = "AISHub: unavailable",
                detail = "The member feed did not answer. Digitraffic remains Finland only.")
            else -> MaritimeRow(
                id = "maritime-aishub",
                title = "AISHub: key required",
                detail = if (keyed) {
                    "The saved key was not used in this refresh. No AISHub request is sent " +
                        "without a key."
                } else {
                    "Ships stay Finland only until a member key is saved in this sheet. " +
                        "No AISHub request is sent without one."
                })
        }

    private fun emptyRow(coverage: String): MaritimeRow = MaritimeRow(
        id = "maritime-empty",
        title = "No ships in this view",
        detail = when (coverage) {
            COVERAGE_OUTSIDE ->
                "The view is outside Digitraffic coverage and no AISHub key is saved."
            COVERAGE_NONE -> "No source answered, so no position is shown."
            else -> "The sources answered with no position inside this box. Pan the map or " +
                "try again later."
        })
}
