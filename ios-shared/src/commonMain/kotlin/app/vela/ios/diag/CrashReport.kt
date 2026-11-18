package app.vela.ios.diag

import kotlin.math.abs
import kotlin.math.round

/**
 * Rule for the crash reports Vela keeps on this phone.
 *
 * iOS only lets an app see an Objective-C exception, so a Swift runtime trap or a segmentation
 * fault never reaches [redact]. What does arrive is written raw to `diagnostics/crashes` and only
 * leaves the phone through the user's own copy or share, after [redact].
 *
 * The report is deliberately free of typed text and place names when it is written, but an
 * exception reason can still quote a URL, a search string or a coordinate. [redact] applies the
 * same rules as Android's `DiagScrub`, which is also the redaction the trip exports document:
 * quoted strings become `[redacted]`, a URL keeps only its host, and coordinate-looking decimals
 * are rounded (two places by default, one when "Redact places in exports" is on).
 *
 * [rotate] keeps the three newest reports. Reports are named `crash-<epochMillis>.txt`, so the
 * oldest are found by the number in the name, never by the directory order.
 */
object CrashReport {
    /** How many crash reports survive a new one. Android keeps five; iOS shows three. */
    const val KEEP = 3

    private val coordLike = Regex("""-?\d{1,3}\.\d{3,}""")
    private val quoted = Regex("\"[^\"]*\"")
    private val url = Regex("""https?://[^\s"'<>]+""")
    private val homePath = Regex("""/(?:Users|home)/[^/\s]+""")

    /** Names of the reports [rotate] deletes, oldest first. Anything else is left untouched. */
    fun rotate(names: List<String>, keep: Int = KEEP): List<String> {
        if (keep < 1) return names
        val crashes = names.filter { it.startsWith("crash-") && it.endsWith(".txt") }
        val ordered = crashes.sortedBy { stampOf(it) }
        if (ordered.size <= keep) return emptyList()
        return ordered.dropLast(keep)
    }

    private fun stampOf(name: String): Long =
        name.removePrefix("crash-").removeSuffix(".txt").toLongOrNull() ?: 0L

    /** The text a copy or a share may hand over, with place-bearing detail removed. */
    fun redact(text: String, redactPlaces: Boolean): String {
        val places = if (redactPlaces) 1 else 2
        var out = coordLike.replace(text) { m ->
            m.value.toDoubleOrNull()?.let { fixed(it, places) } ?: m.value
        }
        out = url.replace(out) { m ->
            val v = m.value
            val end = v.indexOf('/', v.indexOf("//") + 2).let { if (it < 0) v.length else it }
            v.substring(0, end) + "/[redacted]"
        }
        out = homePath.replace(out, "/[home]")
        if (redactPlaces) out = quoted.replace(out, "\"[redacted]\"")
        return out
    }

    /** Locale-independent fixed-point text: the diagnostics file must not follow the device. */
    private fun fixed(value: Double, places: Int): String {
        val scale = if (places == 1) 10L else 100L
        val scaled = round(abs(value) * scale).toLong()
        val whole = scaled / scale
        val fraction = (scaled % scale).toString().padStart(places, '0')
        return (if (value < 0) "-" else "") + whole + "." + fraction
    }
}
