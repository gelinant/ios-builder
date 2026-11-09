package app.vela.core.data.transit

internal actual fun isoEpochSec(iso: String): Long? = portableIsoEpochSec(iso)

internal actual fun stopClockText(epochSec: Long, tz: String?): String = portableClockText(epochSec, tz)
