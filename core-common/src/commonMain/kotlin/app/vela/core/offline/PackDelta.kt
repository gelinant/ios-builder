package app.vela.core.offline

import app.vela.core.platform.SqlCursor
import app.vela.core.platform.SqlDb
import app.vela.core.platform.queryLong

/**
 * Applying a row-level place-pack delta, in one transaction.
 *
 * The bake publishes `del_<table>` and `ins_<table>` in a small SQLite file
 * (`scripts/poipack_delta.py`); the pack has no surrogate keys, so a row is identified by its
 * whole tuple. The Android applier attaches the delta database and joins on that tuple. The
 * shared [SqlDb] seam has no ATTACH, so this reader copies the delta rows first and applies them
 * with bound arguments. Deltas are small (one rebake of a region), and the whole apply stays in a
 * single transaction that is verified against the manifest's per-table counts before commit: a
 * bad patch rolls back rather than leaving a half-updated pack.
 */
object PackDelta {
    sealed class Outcome {
        data class Applied(val rows: Int) : Outcome()
        data class Refused(val why: String) : Outcome()
    }

    /** Table columns, matching `scripts/poipack_build.py` and `scripts/poipack_delta.py`. */
    internal val TABLES: Map<String, List<String>> = mapOf(
        "poi" to listOf("id", "name", "lat", "lng", "category", "address", "phone", "website", "hours"),
        "streetname" to listOf("sid", "street", "street_norm"),
        "addr" to listOf("hn", "sid", "city", "lat", "lng"),
        "streetpt" to listOf("sid", "lat", "lng"),
    )

    private val REAL_COLUMNS = setOf("lat", "lng")
    private val INTEGER_COLUMNS = setOf("sid")

    /** Reads and deletes the rows of [table] present in [delta], then inserts them into [pack]. */
    fun apply(pack: SqlDb, delta: SqlDb, counts: Map<String, Long>): Outcome {
        if (counts.isEmpty()) return Outcome.Refused("manifest has no row counts")
        val rows = HashMap<String, Pair<List<List<Any?>>, List<List<Any?>>>>()
        for ((table, columns) in TABLES) {
            val del = readRows(delta, "del_$table", columns) ?: return Outcome.Refused("delta has no del_$table")
            val ins = readRows(delta, "ins_$table", columns) ?: return Outcome.Refused("delta has no ins_$table")
            rows[table] = del to ins
        }
        return runCatching {
            pack.transaction {
                var total = 0
                for ((table, pair) in rows) {
                    val (del, ins) = pair
                    total += del.size + ins.size
                    val columns = TABLES.getValue(table)
                    val match = columns.joinToString(" AND ") { "$it IS ?" }
                    for (row in del) {
                        pack.execute("DELETE FROM $table WHERE $match", row)
                    }
                    if (ins.isNotEmpty()) {
                        val names = columns.joinToString(",")
                        val marks = columns.joinToString(",") { "?" }
                        for (row in ins) {
                            pack.execute("INSERT INTO $table ($names) VALUES ($marks)", row)
                        }
                    }
                }
                for ((table, expected) in counts) {
                    val got = pack.queryLong("SELECT COUNT(*) FROM $table")
                    check(got == expected) { "$table has $got rows, manifest says $expected" }
                }
                total
            }
            Outcome.Applied(rows.values.sumOf { it.first.size + it.second.size })
        }.getOrElse { Outcome.Refused(it.message?.take(120) ?: it::class.simpleName ?: "error") }
    }

    /** The delta table's rows, null when the table is missing or unreadable. */
    private fun readRows(delta: SqlDb, table: String, columns: List<String>): List<List<Any?>>? = runCatching {
        val out = ArrayList<List<Any?>>()
        delta.query("SELECT ${columns.joinToString(",")} FROM $table") { cursor ->
            out += columns.mapIndexed { i, name -> cell(cursor, i, name) }
        }
        out
    }.getOrNull()

    private fun cell(cursor: SqlCursor, index: Int, column: String): Any? = when {
        cursor.isNull(index) -> null
        column in REAL_COLUMNS -> cursor.getDouble(index)
        column in INTEGER_COLUMNS -> cursor.getLong(index)
        else -> cursor.getString(index) ?: cursor.getLong(index)
    }
}
