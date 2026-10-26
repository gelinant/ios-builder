package app.vela.core.data

import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueStores
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** One remembered search query. [at] = epoch ms it was last used, so the search page
 *  can interleave queries with recently-opened places in ONE chronological list
 *  (Google mixes them; the icon tells them apart). */
@Serializable
data class RecentQuery(val query: String, val at: Long = 0)

/** Most-recent-first list of search queries, persisted locally (capped). */
class RecentSearchStore(
    keyValues: KeyValueStores,
    private val clock: Clock,
) {
    private val prefs = keyValues.open("vela_recents")

    // ignoreUnknownKeys: kept identical to the other stores so a future model change
    // cannot make the decode throw and the getOrDefault(empty) wipe the data.
    private val json = Json { ignoreUnknownKeys = true }

    fun recent(): List<RecentQuery> {
        val raw = prefs.getString(KEY2, null)
        println("RecentSearchStore: key2 bytes=${raw?.length ?: -1}")
        raw?.let { text ->
            runCatching { json.decodeFromString<List<RecentQuery>>(text) }.getOrNull()?.let {
                println("RecentSearchStore: decoded=${it.size}")
                return it
            }
        }
        println("RecentSearchStore: falling back to legacy")
        return migrateLegacy()
    }

    fun add(query: String) {
        val q = query.trim()
        if (q.isEmpty()) return
        val updated = (
            listOf(RecentQuery(q, clock.nowMillis())) +
                recent().filterNot { it.query.equals(q, ignoreCase = true) }
            ).take(MAX)
        prefs.edit().putString(KEY2, json.encodeToString(updated)).apply()
    }

    /** Remove one query (the X on its row). */
    fun remove(query: String) =
        prefs.edit().putString(KEY2, json.encodeToString(recent().filterNot { it.query.equals(query, ignoreCase = true) })).apply()

    fun clear() = prefs.edit().remove(KEY).remove(KEY2).apply()

    /** Pre-timestamp data was a bare string list under [KEY]. Read it once, synthesize
     *  descending timestamps (a minute apart, anchored now) so old entries keep their
     *  order in the merged list, and persist under [KEY2]. [KEY] itself is left alone
     *  so a DOWNGRADED build still finds its old-format data instead of wiping it. */
    private fun migrateLegacy(): List<RecentQuery> {
        val legacy = runCatching { json.decodeFromString<List<String>>(prefs.getString(KEY, "[]") ?: "[]") }
            .getOrDefault(emptyList())
        if (legacy.isEmpty()) return emptyList()
        val now = clock.nowMillis()
        val migrated = legacy.mapIndexed { i, q -> RecentQuery(q, now - i * 60_000L) }
        prefs.edit().putString(KEY2, json.encodeToString(migrated)).apply()
        return migrated
    }

    private companion object {
        const val KEY = "queries" // legacy bare strings (kept in place for downgrades)
        const val KEY2 = "queries2" // timestamped entries
        const val MAX = 8
    }
}
