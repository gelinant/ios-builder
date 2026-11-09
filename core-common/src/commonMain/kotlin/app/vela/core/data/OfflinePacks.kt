package app.vela.core.data

import app.vela.core.platform.SqlDb
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.queryLong
import kotlin.concurrent.Volatile

/**
 * Process-wide registry of downloaded **offline place packs** — per-region SQLite databases baked by
 * CI (`scripts/build-poi-region.sh`) from the region's OSM extract, holding the whole region's named
 * POIs (`poi`), address points (`addr`) and street centerline samples (`street`) in the exact schemas
 * of [OfflinePoiStore] / [OfflineAddressStore]. Both stores query these packs alongside their own
 * Overpass-populated db, so downloading a state makes the whole state searchable offline
 * (Organic-Maps-style), not just the small viewport areas the user saved.
 *
 * The app-side `PoiPackStore` downloads/deletes pack files and calls [reload]; stores read [dbs].
 * Opened read-only and kept for the process lifetime (packs are immutable files; a delete swaps the
 * list first, and any in-flight query on the old handle just finishes).
 */
object OfflinePacks {
    @Volatile private var open: List<SqlDb> = emptyList()

    /** The open pack databases, for the stores to query. */
    val dbs: List<SqlDb> get() = open

    /** (Re)open the packs at [paths] with [sql]; anything unreadable is skipped. Call after
     *  install/delete. */
    fun reload(sql: SqlDbs, paths: List<String>) {
        val fresh = paths.mapNotNull { p ->
            runCatching { sql.openReadOnly(p) }.getOrNull()
        }
        val old = open
        open = fresh
        // Close the handles we replaced (not the ones we just opened for the same path — openDatabase
        // returns distinct handles, so closing old ones never touches the new list).
        old.forEach { runCatching { it.close() } }
    }

    /** Closes every pack, as [reload] with no paths. */
    fun clear() {
        val old = open
        open = emptyList()
        old.forEach { runCatching { it.close() } }
    }

    /** Total rows of [table] across all packs (for "is anything installed" checks). */
    fun count(table: String): Int = open.sumOf { db ->
        runCatching { db.queryLong("SELECT COUNT(*) FROM $table").toInt() }.getOrDefault(0)
    }
}
