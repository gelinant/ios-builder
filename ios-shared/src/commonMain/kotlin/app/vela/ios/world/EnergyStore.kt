package app.vela.ios.world

import kotlin.concurrent.Volatile

/** What one accepted energy refresh holds. The key itself is never a field. */
data class EnergySnapshot(
    val carbon: CarbonSnapshot?,
    val electricityMaps: List<ElectricityMapsReading>,
    val electricityMapsKeyPresent: Boolean,
    val fetchedAtMs: Long,
) {
    /** The oldest feed timestamp, so a fresh fetch never hides a stale carbon forecast. */
    val updatedAtMs: Long
        get() {
            val carbonMs = carbon?.fromMs ?: 0L
            val keyMs = electricityMaps.maxOfOrNull { it.updatedAtMs } ?: 0L
            return when {
                carbonMs > 0L && keyMs > 0L -> minOf(carbonMs, keyMs)
                carbonMs > 0L -> carbonMs
                keyMs > 0L -> keyMs
                else -> fetchedAtMs
            }
        }

    /** `key_required` is an explicit answer, never an empty list that reads as zero carbon. */
    val electricityMapsState: String
        get() = when {
            !electricityMapsKeyPresent -> "key_required"
            electricityMaps.isNotEmpty() -> "ok"
            else -> "no_data"
        }
}

/** The energy layer's freshness. The 30 minute window is the NESO half-hour plus one period. */
data class EnergyState(
    val hasData: Boolean,
    val ageSeconds: Long,
    val status: String,
    val electricityMapsState: String,
)

/**
 * Coordinates the keyless NESO feed and the optional Electricity Maps key. The carbon request
 * always runs; the Electricity Maps request runs only when a non-empty key was passed, so a
 * missing key is a stated state rather than a request with an empty header.
 *
 * No key is kept on this object after [refresh] returns and none is copied into [EnergySnapshot].
 */
class EnergyStore(
    private val carbon: CarbonIntensitySource,
    private val electricityMaps: ElectricityMapsSource,
) {
    @Volatile
    var last: EnergySnapshot? = null
        private set

    suspend fun refresh(
        zones: List<NesoZone>,
        electricityMapsKey: String?,
        nowMs: Long,
    ): EnergySnapshot? {
        val carbonSnapshot = carbon.fetch(zones)
        val key = electricityMapsKey?.trim().orEmpty()
        val keyPresent = key.isNotEmpty()
        val maps = if (keyPresent) {
            electricityMaps.fetch(key, nowMs = nowMs)?.let { listOf(it) }.orEmpty()
        } else {
            emptyList()
        }
        if (carbonSnapshot == null && maps.isEmpty()) return null
        val snapshot = EnergySnapshot(
            carbon = carbonSnapshot,
            electricityMaps = maps,
            electricityMapsKeyPresent = keyPresent,
            fetchedAtMs = nowMs,
        )
        last = snapshot
        return snapshot
    }

    fun state(nowMs: Long): EnergyState = stateOf(last, nowMs)

    fun stateOf(snapshot: EnergySnapshot?, nowMs: Long): EnergyState {
        if (snapshot == null) {
            return EnergyState(false, 0L, WorldLayerStatuses.UNAVAILABLE, "no_data")
        }
        val ageSeconds = ((nowMs - snapshot.updatedAtMs).coerceAtLeast(0L)) / 1_000L
        val status = when {
            ageSeconds > MAX_AGE_SECONDS -> WorldLayerStatuses.LATE
            else -> WorldLayerStatuses.FRESH
        }
        return EnergyState(
            hasData = true,
            ageSeconds = ageSeconds,
            status = status,
            electricityMapsState = snapshot.electricityMapsState,
        )
    }

    companion object {
        /** The layer's own window, also used by `WorldLayerCatalog.ENERGY`. */
        const val MAX_AGE_SECONDS = 30L * 60L
        const val MAX_AGE_MS = MAX_AGE_SECONDS * 1_000L
    }
}
