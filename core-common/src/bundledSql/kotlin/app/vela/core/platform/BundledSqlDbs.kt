package app.vela.core.platform

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_CREATE
import androidx.sqlite.driver.bundled.SQLITE_OPEN_FULLMUTEX
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READWRITE
import androidx.sqlite.execSQL
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/**
 * [SqlDbs] over the SQLite that `androidx.sqlite:sqlite-bundled` compiles in (the iOS
 * implementation; the JVM tests run the same file). One connection per database, every call
 * under one lock; default journal mode, as on Android. [databaseDir] holds the databases [open]
 * names; [ensureDir] creates it before the first one opens.
 */
class BundledSqlDbs(
    private val databaseDir: String,
    private val ensureDir: (String) -> Unit = {},
) : SqlDbs {
    private val driver = BundledSQLiteDriver()

    override fun open(name: String, version: Int, onCreate: (SqlDb) -> Unit, onUpgrade: (SqlDb, Int, Int) -> Unit): SqlDb {
        val path = if (name.startsWith("/")) name else joinPath(databaseDir, name)
        return BundledSqlDb {
            if (!name.startsWith("/")) ensureDir(databaseDir)
            driver.open(path, SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE or SQLITE_OPEN_FULLMUTEX)
        }.also { it.versioned(version, onCreate, onUpgrade) }
    }

    override fun openReadOnly(path: String): SqlDb {
        val c = driver.open(path, SQLITE_OPEN_READONLY or SQLITE_OPEN_FULLMUTEX)
        // SQLite opens lazily: read the schema now so a file that is not a database fails here.
        try {
            c.prepare("SELECT count(*) FROM sqlite_master").use { it.step() }
        } catch (e: Throwable) {
            c.close()
            throw e
        }
        return BundledSqlDb { c }
    }
}

private class BundledSqlDb(private val connect: () -> SQLiteConnection) : SqlDb {
    private val lock = SynchronizedObject()
    private var conn: SQLiteConnection? = null
    private var setUp: ((SqlDb) -> Unit)? = null
    private var depth = 0

    fun versioned(version: Int, onCreate: (SqlDb) -> Unit, onUpgrade: (SqlDb, Int, Int) -> Unit) {
        setUp = { db ->
            val old = db.queryLong("PRAGMA user_version").toInt()
            if (old != version) {
                if (old > version) throw IllegalStateException("Can't downgrade database from version $old to $version")
                db.transaction {
                    if (old == 0) onCreate(db) else onUpgrade(db, old, version)
                    db.execute("PRAGMA user_version = $version")
                }
            }
        }
    }

    private fun c(): SQLiteConnection {
        conn?.let { return it }
        val fresh = connect()
        conn = fresh
        val s = setUp
        setUp = null
        if (s != null) {
            try {
                s(this)
            } catch (e: Throwable) {
                conn = null
                setUp = s
                fresh.close()
                throw e
            }
        }
        return fresh
    }

    override fun execute(sql: String, args: List<Any?>) = synchronized(lock) {
        c().prepare(sql).use { st ->
            bind(st, args)
            st.step()
        }
        Unit
    }

    override fun query(sql: String, args: List<Any?>, row: (SqlCursor) -> Unit) = synchronized(lock) {
        c().prepare(sql).use { st ->
            bind(st, args)
            val view = StatementView(st)
            while (st.step()) row(view)
        }
    }

    override fun <T> transaction(block: () -> T): T = synchronized(lock) {
        val c = c()
        if (depth > 0) return@synchronized block()
        c.execSQL("BEGIN EXCLUSIVE")
        depth++
        try {
            val out = block()
            c.execSQL("COMMIT")
            out
        } catch (e: Throwable) {
            runCatching { c.execSQL("ROLLBACK") }
            throw e
        } finally {
            depth--
        }
    }

    override fun close() = synchronized(lock) {
        conn?.close()
        conn = null
    }

    private fun bind(st: SQLiteStatement, args: List<Any?>) {
        args.forEachIndexed { i, a ->
            val at = i + 1
            when (a) {
                null -> st.bindNull(at)
                is String -> st.bindText(at, a)
                is Double -> st.bindDouble(at, a)
                is Float -> st.bindDouble(at, a.toDouble())
                is Long -> st.bindLong(at, a)
                is Int -> st.bindLong(at, a.toLong())
                is Short -> st.bindLong(at, a.toLong())
                is Byte -> st.bindLong(at, a.toLong())
                is Boolean -> st.bindLong(at, if (a) 1 else 0)
                is ByteArray -> st.bindBlob(at, a)
                else -> st.bindText(at, a.toString())
            }
        }
    }
}

private class StatementView(private val st: SQLiteStatement) : SqlCursor {
    override fun getLong(index: Int): Long = st.getLong(index)
    override fun getDouble(index: Int): Double = st.getDouble(index)
    override fun getString(index: Int): String? = if (st.isNull(index)) null else st.getText(index)
    override fun getBlob(index: Int): ByteArray? = if (st.isNull(index)) null else st.getBlob(index)
    override fun isNull(index: Int): Boolean = st.isNull(index)
}
