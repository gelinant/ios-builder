package app.vela.core.platform

/** The current row of a [SqlDb.query], read by column index from 0. */
interface SqlCursor {
    fun getLong(index: Int): Long
    fun getDouble(index: Int): Double

    /** The column as text, null when it is SQL NULL. */
    fun getString(index: Int): String?

    /** The column as bytes, null when it is SQL NULL. */
    fun getBlob(index: Int): ByteArray?
    fun isNull(index: Int): Boolean
}

/**
 * One SQLite database (SPEC "Platform seams"). Arguments bind by type: `String` as text, `Long`,
 * `Int`, `Short`, `Byte` and `Boolean` as integers, `Double` and `Float` as reals, `ByteArray` as
 * a blob, null as NULL. Errors throw (`android.database.SQLException` on Android).
 */
interface SqlDb {
    /** Runs one statement that returns no rows. */
    fun execute(sql: String, args: List<Any?> = emptyList())

    /** Runs a query and calls [row] once per row, in order, with the cursor on that row. The
     *  cursor is only valid during the call. */
    fun query(sql: String, args: List<Any?> = emptyList(), row: (SqlCursor) -> Unit)

    /** Runs [block] in an exclusive transaction: committed when it returns, rolled back when it
     *  throws. A transaction opened inside another joins it. */
    fun <T> transaction(block: () -> T): T

    fun close()
}

/**
 * Opens databases. [open] behaves as Android's `SQLiteOpenHelper`: the database opens on first
 * use, not here; when its `user_version` is 0 [onCreate] runs, when it is lower than [version]
 * [onUpgrade] runs with the old and new versions, both inside one transaction that then sets
 * `user_version` to [version]. A database newer than [version] fails to open.
 */
interface SqlDbs {
    /** A writable database called [name] in the platform's database folder (an absolute path is
     *  used as is). Android: `Context.getDatabasePath`. */
    fun open(name: String, version: Int, onCreate: (SqlDb) -> Unit, onUpgrade: (SqlDb, Int, Int) -> Unit): SqlDb

    /** An existing database file opened read-only, at once. Throws when it cannot be opened. */
    fun openReadOnly(path: String): SqlDb
}

/** The first column of the first row as a Long, or [default] when there is no row. */
fun SqlDb.queryLong(sql: String, args: List<Any?> = emptyList(), default: Long = 0L): Long {
    var out: Long? = null
    query(sql, args) { if (out == null) out = it.getLong(0) }
    return out ?: default
}
