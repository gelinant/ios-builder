package app.vela.core.platform

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteCursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.database.sqlite.SQLiteProgram

/** [SqlDbs] over the platform SQLite. [open] is a `SQLiteOpenHelper` (default journal mode, no
 *  WAL, as the stores had), [openReadOnly] is `SQLiteDatabase.openDatabase` with `OPEN_READONLY`. */
class AndroidSqlDbs(private val context: Context) : SqlDbs {
    override fun open(name: String, version: Int, onCreate: (SqlDb) -> Unit, onUpgrade: (SqlDb, Int, Int) -> Unit): SqlDb {
        val helper = object : SQLiteOpenHelper(context, name, null, version) {
            override fun onCreate(db: SQLiteDatabase) = onCreate(AndroidSqlDb({ db }, { db }, {}))
            override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) =
                onUpgrade(AndroidSqlDb({ db }, { db }, {}), oldVersion, newVersion)
        }
        // Reads take readableDatabase and writes writableDatabase, as the stores did.
        return AndroidSqlDb({ helper.readableDatabase }, { helper.writableDatabase }, helper::close)
    }

    override fun openReadOnly(path: String): SqlDb {
        val db = SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
        return AndroidSqlDb({ db }, { db }, db::close)
    }
}

private class AndroidSqlDb(
    private val read: () -> SQLiteDatabase,
    private val write: () -> SQLiteDatabase,
    private val onClose: () -> Unit,
) : SqlDb {
    override fun execute(sql: String, args: List<Any?>) {
        if (args.isEmpty()) write().execSQL(sql) else write().execSQL(sql, args.toTypedArray())
    }

    override fun query(sql: String, args: List<Any?>, row: (SqlCursor) -> Unit) {
        val db = read()
        // String arguments go through rawQuery, the call the stores made; others bind by type.
        val cursor = if (args.all { it is String }) {
            db.rawQuery(sql, args.map { it as String }.toTypedArray())
        } else {
            db.rawQueryWithFactory({ _, driver, table, q -> bind(q, args); SQLiteCursor(driver, table, q) }, sql, null, "")
        }
        cursor.use { c ->
            val view = CursorView(c)
            while (c.moveToNext()) row(view)
        }
    }

    override fun <T> transaction(block: () -> T): T {
        val db = write()
        db.beginTransaction()
        try {
            val out = block()
            db.setTransactionSuccessful()
            return out
        } finally {
            db.endTransaction()
        }
    }

    override fun close() = onClose()

    private fun bind(q: SQLiteProgram, args: List<Any?>) {
        args.forEachIndexed { i, a ->
            val at = i + 1
            when (a) {
                null -> q.bindNull(at)
                is String -> q.bindString(at, a)
                is Double -> q.bindDouble(at, a)
                is Float -> q.bindDouble(at, a.toDouble())
                is Long -> q.bindLong(at, a)
                is Int -> q.bindLong(at, a.toLong())
                is Short -> q.bindLong(at, a.toLong())
                is Byte -> q.bindLong(at, a.toLong())
                is Boolean -> q.bindLong(at, if (a) 1 else 0)
                is ByteArray -> q.bindBlob(at, a)
                else -> q.bindString(at, a.toString())
            }
        }
    }
}

private class CursorView(private val c: Cursor) : SqlCursor {
    override fun getLong(index: Int): Long = c.getLong(index)
    override fun getDouble(index: Int): Double = c.getDouble(index)
    override fun getString(index: Int): String? = c.getString(index)
    override fun getBlob(index: Int): ByteArray? = c.getBlob(index)
    override fun isNull(index: Int): Boolean = c.isNull(index)
}
