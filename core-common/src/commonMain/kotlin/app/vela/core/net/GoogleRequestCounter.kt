package app.vela.core.net

import kotlin.concurrent.Volatile
import kotlin.time.Clock
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.TimeZone
import kotlinx.datetime.minus
import kotlinx.datetime.todayIn
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * How many requests this phone sent to which Google server, by purpose and by day (SET-PRIVACY).
 *
 * The count lives only on the phone: iOS shows it on Settings > Privacy and writes it to the
 * diagnostics export; nothing is uploaded. [GoogleUsage] already counts the same traffic by purpose
 * on Android, but it keeps no host and does not survive a relaunch by itself. This counter stores
 * both, plus the requests "Use Vela without Google" refused on the phone, and serializes to one
 * string ([save]) that the app keeps in its settings store.
 *
 * Counted: every request the main HTTP client sends to a Google host, passed here with its URL so
 * the host is exact and the purpose comes from [GoogleUsage.kindOf]. NOT counted: map tiles a map
 * engine fetches itself, and the traffic of a hidden WebView. The UI says so.
 */
/** One line of the Privacy page: a purpose or a host, today and over the last seven days. */
data class GoogleRequestRow(val label: String, val today: Int, val week: Int)

object GoogleRequestCounter {
    /** Days kept by [restore] and [save], today included. */
    const val KEEP_DAYS = 14

    /** One day's counts. Maps are sorted by key so a saved string is deterministic. */
    @Serializable
    data class DayUsage(
        val sent: Map<String, Int> = emptyMap(),
        val kinds: Map<String, Int> = emptyMap(),
        val blocked: Map<String, Int> = emptyMap(),
    )

    @Serializable
    private data class Saved(val version: Int = 1, val days: Map<String, DayUsage> = emptyMap())

    private val lock = SynchronizedObject()
    private val days = HashMap<String, MutableDay>()
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /** Called after every change, so the app can persist without knowing the shape. */
    @Volatile
    var onChange: (() -> Unit)? = null

    private class MutableDay {
        val sent = HashMap<String, Int>()
        val kinds = HashMap<String, Int>()
        val blocked = HashMap<String, Int>()

        fun toUsage() = DayUsage(
            sent = sent.sorted(),
            kinds = kinds.sorted(),
            blocked = blocked.sorted(),
        )

        private fun Map<String, Int>.sorted(): Map<String, Int> =
            entries.sortedBy { it.key }.associate { it.key to it.value }
    }

    /** The phone's local date, the key of a day. Test callers pass their own day. */
    fun today(): String = Clock.System.todayIn(TimeZone.currentSystemDefault()).toString()

    /**
     * Counts one request that left the phone. [url] is parsed for its host, path and query, so a
     * lookalike host is not counted and the purpose is the same one [GoogleUsage] names.
     * [kind] overrides the URL classification when the caller knows better.
     */
    fun recordSentUrl(url: String, kind: String?, day: String) {
        val parts = parts(url)
        if (!GoogleUsage.isGoogle(parts.host)) return
        recordSentHost(parts.host, kind ?: GoogleUsage.kindOf(parts.host, parts.path, parts.query), day)
    }

    /** Counts one request to [host], already known to be Google's. */
    fun recordSentHost(host: String, kind: String, day: String) {
        val h = normalize(host)
        if (h.isEmpty()) return
        val k = if (kind.isBlank()) "other" else kind
        synchronized(lock) {
            val d = days.getOrPut(day) { MutableDay() }
            d.sent[h] = (d.sent[h] ?: 0) + 1
            d.kinds[k] = (d.kinds[k] ?: 0) + 1
        }
        onChange?.invoke()
    }

    /** Counts one request to a Google host that "Use Vela without Google" refused on the phone. */
    fun recordBlockedUrl(url: String, day: String) {
        val host = parts(url).host
        if (!GoogleUsage.isGoogle(host)) return
        recordBlockedHost(host, day)
    }

    fun recordBlockedHost(host: String, day: String) {
        val h = normalize(host)
        if (h.isEmpty()) return
        synchronized(lock) {
            val d = days.getOrPut(day) { MutableDay() }
            d.blocked[h] = (d.blocked[h] ?: 0) + 1
        }
        onChange?.invoke()
    }

    /** Day -> counts, newest day first, at most [KEEP_DAYS] days. */
    fun snapshot(): Map<String, DayUsage> = synchronized(lock) {
        days.entries.sortedByDescending { it.key }.take(KEEP_DAYS)
            .associate { (day, d) -> day to d.toUsage() }
    }

    /** Purpose of every counted request over the last seven days, busiest first. */
    fun rows(): List<GoogleRequestRow> = weekRows(byHost = false)

    /** Host of every counted request over the last seven days, busiest first. */
    fun hostRows(): List<GoogleRequestRow> = weekRows(byHost = true)

    fun totalToday(): Int = synchronized(lock) {
        days[today()]?.sent?.values?.sum() ?: 0
    }

    fun totalWeek(): Int = weekTotals(byHost = false).values.sum()

    fun blockedToday(): Int = synchronized(lock) {
        days[today()]?.blocked?.values?.sum() ?: 0
    }

    /** Requests per day over the last seven days that had any, rounded down. */
    fun dailyAverage(): Int {
        val totals = synchronized(lock) {
            val from = weekStart()
            days.filterKeys { it >= from }.values.map { it.sent.values.sum() }.filter { it > 0 }
        }
        return if (totals.isEmpty()) 0 else totals.sum() / totals.size
    }

    /** The Debug line the UI scenarios read through the settings screen. */
    fun debugLine(): String = "greq=${totalToday()} gblocked=${blockedToday()}"

    /** Drops every count. Saved places, trips and every other store are untouched. */
    fun clear() {
        synchronized(lock) { days.clear() }
        onChange?.invoke()
    }

    /** The string the app persists. Empty counts save as an empty object, never as an error. */
    fun save(): String = json.encodeToString(Saved(days = snapshot()))

    /** Loads a saved string, merges it into what this process counted and drops old days. */
    fun restore(text: String) {
        if (text.isBlank()) return
        val saved = runCatching { json.decodeFromString<Saved>(text) }.getOrNull() ?: return
        val cutoff = Clock.System.todayIn(TimeZone.currentSystemDefault())
            .minus(KEEP_DAYS, DateTimeUnit.DAY).toString()
        synchronized(lock) {
            saved.days.filterKeys { it > cutoff }.forEach { (day, usage) ->
                val d = days.getOrPut(day) { MutableDay() }
                usage.sent.forEach { (k, n) -> d.sent[k] = (d.sent[k] ?: 0) + n }
                usage.kinds.forEach { (k, n) -> d.kinds[k] = (d.kinds[k] ?: 0) + n }
                usage.blocked.forEach { (k, n) -> d.blocked[k] = (d.blocked[k] ?: 0) + n }
            }
            days.keys.filter { it <= cutoff }.forEach { days.remove(it) }
        }
    }

    private fun weekRows(byHost: Boolean): List<GoogleRequestRow> {
        val totals = weekTotals(byHost)
        val todayMap = synchronized(lock) {
            val d = days[today()] ?: MutableDay()
            if (byHost) d.sent.toMap() else d.kinds.toMap()
        }
        return totals.entries
            .sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
            .map { GoogleRequestRow(it.key, todayMap[it.key] ?: 0, it.value) }
    }

    private fun weekTotals(byHost: Boolean): Map<String, Int> = synchronized(lock) {
        val from = weekStart()
        val totals = HashMap<String, Int>()
        days.filterKeys { it >= from }.values.forEach { d ->
            val source = if (byHost) d.sent else d.kinds
            source.forEach { (k, n) -> totals[k] = (totals[k] ?: 0) + n }
        }
        totals
    }

    private fun weekStart(): String =
        Clock.System.todayIn(TimeZone.currentSystemDefault())
            .minus(6, DateTimeUnit.DAY).toString()

    private data class Parts(val host: String, val path: String, val query: String?)

    /** A URL's host, path and query, without a platform URL type. */
    private fun parts(url: String): Parts {
        val noScheme = url.substringAfter("://", url)
        val authority = noScheme.substringBefore('/').substringBefore('?').substringBefore('#')
        val host = normalize(authority.substringAfter('@').substringBefore(':'))
        val rest = if ('/' in noScheme) noScheme.substringAfter('/') else ""
        val rawPath = rest.substringBefore('?').substringBefore('#')
        val path = if (rawPath.isEmpty()) "/" else "/$rawPath"
        val query = rest.substringAfter('?', "").substringBefore('#').ifBlank { null }
        return Parts(host, path, query)
    }

    private fun normalize(host: String): String = host.trim().lowercase().trimEnd('.')
}
