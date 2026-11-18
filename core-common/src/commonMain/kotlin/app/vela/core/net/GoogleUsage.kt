package app.vela.core.net

import kotlin.concurrent.Volatile
import kotlin.time.Clock
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.todayIn

/**
 * How many requests Vela sends to Google, by purpose and by day, counted on the phone and never
 * sent anywhere (2026-09-25). "Vela uses Google sparingly" should be a number: Settings > Privacy
 * shows it and the diagnostics export carries it, so the next cut in Google traffic goes where the
 * volume actually is.
 *
 * Counted: every request to a Google host through the shared HTTP client (Android: `GoogleTransport.hook`
 * calls [record], whether Cronet or OkHttp carries it), tagged with its purpose by the caller
 * ([Kind]) or classified from the URL ([kindOf]); and every hidden Google page load (the app counts
 * those where they start, and every request such a page makes after it loads, as "page resources").
 * NOT counted: map tiles MapLibre fetches itself (the live-traffic layer, satellite imagery past
 * Esri's coverage).
 */
object GoogleUsage {
    /** The purpose of a Google request, as the caller names it (`RequestTags.usageKind`; on
     *  Android the OkHttp request tag the shared client's hook reads). */
    data class Kind(val name: String)

    private val lock = SynchronizedObject()
    private val days = HashMap<String, HashMap<String, Int>>()

    /** Called after every change (the app saves on it, debounced). */
    @Volatile var onChange: (() -> Unit)? = null

    /** Retention: days kept by [restore] and [snapshot]. */
    const val KEEP_DAYS = 14

    fun today(): String = Clock.System.todayIn(TimeZone.currentSystemDefault()).toString()

    fun record(kind: String, day: String = today()) {
        synchronized(lock) {
            val kinds = days.getOrPut(day) { HashMap() }
            kinds[kind] = (kinds[kind] ?: 0) + 1
        }
        onChange?.invoke()
    }

    /** Is [host] Google's? The hosts Vela's requests and images reach. */
    fun isGoogle(host: String): Boolean {
        val h = host.lowercase()
        return listOf("google.com", "googleapis.com", "gstatic.com", "googleusercontent.com", "ggpht.com")
            .any { h == it || h.endsWith(".$it") }
    }

    /** The purpose of an untagged Google request, read off its URL. */
    fun kindOf(host: String, path: String, query: String?): String {
        val h = host.lowercase()
        val q = query.orEmpty()
        return when {
            h.endsWith("googleusercontent.com") || h.endsWith("ggpht.com") || h.endsWith("gstatic.com") -> "images"
            h.startsWith("streetviewpixels") || path.contains("GeoPhotoService") || path.contains("/photometa/") -> "street view"
            path.contains("batchexecute") && q.contains("hspqX") -> "photos"
            path.contains("batchexecute") && q.contains("qv9Egd") -> "reviews"
            path.startsWith("/maps/preview/directions") -> "directions"
            path == "/s" -> "suggestions"
            path == "/search" -> "search"
            path.startsWith("/maps") && q.isEmpty() || path == "/maps" -> "session"
            else -> "other"
        }
    }

    /** Day -> kind -> count, newest day first, at most [KEEP_DAYS] days. */
    fun snapshot(): Map<String, Map<String, Int>> = synchronized(lock) {
        days.entries.sortedByDescending { it.key }.take(KEEP_DAYS)
            .associate { (day, kinds) -> day to kinds.entries.sortedBy { it.key }.associate { it.key to it.value } }
    }

    /** Load saved days (the app's store), dropping anything older than [KEEP_DAYS]. */
    fun restore(saved: Map<String, Map<String, Int>>) {
        val cutoff = Clock.System.todayIn(TimeZone.currentSystemDefault()).minus(KEEP_DAYS, DateTimeUnit.DAY).toString()
        synchronized(lock) {
            saved.filterKeys { it > cutoff }.forEach { (day, kinds) ->
                val m = days.getOrPut(day) { HashMap() }
                kinds.forEach { (k, n) -> m[k] = (m[k] ?: 0) + n }
            }
            days.keys.filter { it <= cutoff }.forEach { days.remove(it) }
        }
    }

    /** Clear everything (tests, and a user resetting the count). */
    fun reset() {
        synchronized(lock) { days.clear() }
        onChange?.invoke()
    }
}
