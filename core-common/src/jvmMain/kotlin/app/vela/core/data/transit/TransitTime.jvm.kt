package app.vela.core.data.transit

import app.vela.core.data.ClockFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal actual fun isoEpochSec(iso: String): Long? = runCatching { java.time.Instant.parse(iso).epochSecond }.getOrNull()

internal actual fun stopClockText(epochSec: Long, tz: String?): String {
    val fmt = SimpleDateFormat(if (ClockFormat.use24h) "HH:mm" else "h:mm a", Locale.US)
    fmt.timeZone = tz?.let { runCatching { TimeZone.getTimeZone(it) }.getOrNull() } ?: TimeZone.getDefault()
    return fmt.format(Date(epochSec * 1000))
}
