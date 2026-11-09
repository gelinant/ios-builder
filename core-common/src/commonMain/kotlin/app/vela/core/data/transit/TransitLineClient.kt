package app.vela.core.data.transit

import app.vela.core.VelaConfig
import app.vela.core.data.google.PolylineCodec
import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.util.UrlCodec
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * One stop of a run's FULL sequence, in the order the vehicle calls at it. [expectedEpochSec] is
 * the time the feed currently shows (real-time when the run is tracked), [scheduledEpochSec] the
 * timetable time. [clockText] and [scheduledText] are already in the stop's own timezone; the
 * latter is filled only when the live call moved away from the timetable.
 */
data class TransitLineRunStop(
    val name: String,
    val stopId: String?,
    val code: String?,
    val latitude: Double,
    val longitude: Double,
    val expectedEpochSec: Long?,
    val scheduledEpochSec: Long?,
    val clockText: String?,
    val scheduledText: String?,
    val tz: String?,
    val canceled: Boolean,
)

/**
 * The whole scheduled run behind one departure: every stop from the run's origin to its terminus,
 * with the feed's own times. [shape] is the run's drawn path from `legGeometry`; empty when the
 * feed sent none, and then nothing is invented on the map.
 */
data class TransitLineRun(
    val tripId: String,
    val label: String?,
    val headsign: String?,
    val mode: TransitMode,
    val colorHex: String?,
    val textColorHex: String?,
    val realTime: Boolean,
    val canceled: Boolean,
    val shape: List<LatLng>,
    val stops: List<TransitLineRunStop>,
)

/**
 * The full stop sequence of one run, read from Transitous `/api/v1/trip`.
 *
 * `Transitous.tripStops` trims its answer at the tapped stop because the ride timeline boards
 * there; the line sheet needs the run from its origin, and the ribbon needs the epochs the
 * estimated vehicle position interpolates between. Both come from this client, which is separate
 * so that no existing call site changes behavior. Null on any failure, and a run with fewer than
 * two stops is not a sequence: the sheet then shows only the departures the board sent.
 */
object TransitLineClient {
    private val json = Json { ignoreUnknownKeys = true }
    private const val TIMEOUT_MS = 20_000L

    suspend fun run(http: TransitousHttp, tripId: String): TransitLineRun? {
        if (tripId.isBlank()) return null
        val url = Transitous.BASE + "/api/v1/trip?tripId=" + UrlCodec.encode(tripId)
        val body = fetch(http, withLanguage(url, http.locale.defaultLanguage())) ?: return null
        return parseRun(body.decodeToString(), tripId)
    }

    /** Public for the JVM test: a `/api/v1/trip` body as a run, null when it carries no sequence. */
    fun parseRun(text: String, tripId: String): TransitLineRun? {
        val leg = runCatching { json.decodeFromString<TripReply>(text).legs.firstOrNull() }
            .getOrNull() ?: return null
        return runOf(leg, tripId)
    }

    /** Public for the fixture test: the pure mapping of one trip leg. */
    fun runOf(leg: TripLegDto, tripId: String): TransitLineRun? {
        val stops = (listOf(leg.from) + leg.intermediateStops + listOf(leg.to))
            .filter { it.name.isNotBlank() }
            .map { stop ->
                val expected = stop.departure ?: stop.arrival
                val scheduled = stop.scheduledDeparture ?: stop.scheduledArrival
                val expectedEpoch = expected?.let { isoEpochSec(it) }
                val scheduledEpoch = scheduled?.let { isoEpochSec(it) }
                TransitLineRunStop(
                    name = stop.name,
                    stopId = stop.stopId.takeIf { it.isNotBlank() },
                    code = stop.stopCode?.takeIf { it.isNotBlank() },
                    latitude = stop.lat,
                    longitude = stop.lon,
                    expectedEpochSec = expectedEpoch,
                    scheduledEpochSec = scheduledEpoch,
                    clockText = expectedEpoch?.let { stopClockText(it, stop.tz) },
                    scheduledText = if (expectedEpoch != null && scheduledEpoch != null && expectedEpoch != scheduledEpoch) {
                        stopClockText(scheduledEpoch, stop.tz)
                    } else {
                        null
                    },
                    tz = stop.tz,
                    canceled = stop.cancelled || leg.cancelled,
                )
            }
        if (stops.size < 2) return null
        val shape = leg.legGeometry?.points?.takeIf { it.isNotBlank() }?.let {
            runCatching { PolylineCodec.decode(it, leg.legGeometry.precision) }.getOrNull()
        }.orEmpty()
        return TransitLineRun(
            tripId = tripId,
            label = leg.routeShortName?.takeIf { it.isNotBlank() } ?: leg.displayName?.takeIf { it.isNotBlank() },
            headsign = leg.headsign?.takeIf { it.isNotBlank() },
            mode = modeOf(leg.mode),
            colorHex = colorOf(leg.routeColor),
            textColorHex = colorOf(leg.routeTextColor),
            realTime = leg.realTime,
            canceled = leg.cancelled,
            shape = shape,
            stops = stops,
        )
    }

    /** "#rrggbb" when the feed sent a usable color, null otherwise. Never a guessed color. */
    fun colorOf(color: String?): String? {
        val hex = color?.trim()?.removePrefix("#")?.lowercase() ?: return null
        return "#$hex".takeIf { hex.length == 6 && hex.all { c -> c in '0'..'9' || c in 'a'..'f' } }
    }

    fun modeOf(mode: String?): TransitMode = when (mode?.uppercase()) {
        "BUS", "COACH" -> TransitMode.BUS
        "TRAM" -> TransitMode.TRAM
        "SUBWAY", "METRO" -> TransitMode.SUBWAY
        "RAIL", "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL" -> TransitMode.TRAIN
        "FERRY" -> TransitMode.FERRY
        else -> TransitMode.GENERIC
    }

    /** The app's language where the feed has names for it, the same rule as [Transitous]. */
    private fun withLanguage(url: String, language: String): String {
        val lang = when (val l = language.lowercase()) { "iw" -> "he"; "in" -> "id"; "ji" -> "yi"; else -> l }
        if (lang.length !in 2..3 || "language=" in url) return url
        return url + (if ('?' in url) "&" else "?") + "language=" + lang
    }

    private suspend fun fetch(http: TransitousHttp, url: String): ByteArray? {
        val response = try {
            http.http.call(
                HttpRequest(
                    url,
                    headers = listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA)),
                    timeoutMillis = TIMEOUT_MS,
                ),
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            return null
        }
        return if (response.isSuccessful) response.body else null
    }

    @Serializable
    private data class TripReply(val legs: List<TripLegDto> = emptyList())

    @Serializable
    data class TripLegDto(
        val from: TripStopDto = TripStopDto(),
        val to: TripStopDto = TripStopDto(),
        val intermediateStops: List<TripStopDto> = emptyList(),
        val mode: String? = null,
        val headsign: String? = null,
        val routeShortName: String? = null,
        val displayName: String? = null,
        val routeColor: String? = null,
        val routeTextColor: String? = null,
        val realTime: Boolean = false,
        val cancelled: Boolean = false,
        val legGeometry: GeometryDto? = null,
    )

    @Serializable
    data class TripStopDto(
        val name: String = "",
        val stopId: String = "",
        val lat: Double = 0.0,
        val lon: Double = 0.0,
        val arrival: String? = null,
        val departure: String? = null,
        val scheduledArrival: String? = null,
        val scheduledDeparture: String? = null,
        val cancelled: Boolean = false,
        val tz: String? = null,
        val stopCode: String? = null,
    )

    @Serializable
    data class GeometryDto(val points: String = "", val precision: Int = 6)
}
