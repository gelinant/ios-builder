package app.vela.core.data.transit

import app.vela.core.data.ClockFormat
import kotlin.time.Instant
import kotlinx.datetime.TimeZone

/** ISO-8601 instant ("2026-07-13T20:26:00Z") to epoch seconds, null when it does not parse. The
 *  JVM keeps `java.time.Instant.parse`, so each Android version reads what it read before; native
 *  is [portableIsoEpochSec]. */
internal expect fun isoEpochSec(iso: String): Long?

/** [epochSec] on the clock in use ([ClockFormat.use24h]) in the zone named [tz], the process zone
 *  when null. The JVM keeps `SimpleDateFormat` and `java.util.TimeZone` (an unknown name is GMT);
 *  native is [portableClockText]. */
internal expect fun stopClockText(epochSec: Long, tz: String?): String

internal fun portableIsoEpochSec(iso: String): Long? = runCatching { Instant.parse(iso).epochSeconds }.getOrNull()

/** An unknown zone name is UTC, as `TimeZone.getTimeZone` makes it GMT. */
internal fun portableClockText(epochSec: Long, tz: String?): String {
    val zone = if (tz == null) TimeZone.currentSystemDefault() else runCatching { TimeZone.of(tz) }.getOrElse { TimeZone.UTC }
    return ClockFormat.at(epochSec, zone)
}
