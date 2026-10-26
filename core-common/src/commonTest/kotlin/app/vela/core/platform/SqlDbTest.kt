package app.vela.core.platform

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The [SqlDbs] contract, run against the bundled SQLite on the JVM and on the iOS simulator. */
class SqlDbTest {
    private fun SqlDbs.openT(dir: String, version: Int, log: MutableList<String>): SqlDb = open(
        joinPath(dir, "t.db"), version,
        onCreate = { log += "create"; it.execute("CREATE TABLE t(a INTEGER, b REAL, c TEXT, d BLOB)") },
        onUpgrade = { db, old, new -> log += "upgrade $old $new"; db.execute("ALTER TABLE t ADD COLUMN e TEXT") },
    )

    @Test fun createRunsOnceThenUpgradeWithTheVersions() {
        val dir = newTestDir()
        val log = ArrayList<String>()
        val first = newTestSqlDbs(dir).openT(dir, 2, log)
        assertEquals(emptyList(), log, "opening is lazy")
        assertEquals(2L, first.queryLong("PRAGMA user_version"))
        first.close()
        newTestSqlDbs(dir).openT(dir, 2, log).also { it.queryLong("SELECT 1") }.close()
        val third = newTestSqlDbs(dir).openT(dir, 3, log)
        assertEquals(3L, third.queryLong("PRAGMA user_version"))
        assertEquals(listOf("create", "upgrade 2 3"), log)
        third.close()
        assertFailsWith<Throwable> { newTestSqlDbs(dir).openT(dir, 1, log).queryLong("SELECT 1") }
    }

    @Test fun argumentsBindByType() {
        val dir = newTestDir()
        val db = newTestSqlDbs(dir).openT(dir, 1, ArrayList())
        db.execute("INSERT INTO t(a,b,c,d) VALUES (?,?,?,?)", listOf(7_000_000_000L, 1.5, "x", byteArrayOf(1, 2)))
        db.execute("INSERT INTO t(a,b,c,d) VALUES (?,?,?,?)", listOf(3, 2.5f, null, null))
        val rows = ArrayList<List<Any?>>()
        db.query("SELECT a,b,c,d,typeof(a),typeof(b) FROM t ORDER BY a DESC") { c ->
            rows += listOf(c.getLong(0), c.getDouble(1), c.getString(2), c.getBlob(3)?.toList(), c.getString(4), c.getString(5), c.isNull(2))
        }
        assertEquals(listOf(7_000_000_000L, 1.5, "x", listOf<Byte>(1, 2), "integer", "real", false), rows[0])
        assertEquals(listOf(3L, 2.5, null, null, "integer", "real", true), rows[1])
        // A String argument compares with a REAL column numerically, as the stores' boxes do.
        assertEquals(1L, db.queryLong("SELECT COUNT(*) FROM t WHERE b BETWEEN ? AND ?", listOf("1.0", "2.0")))
        db.close()
    }

    @Test fun aTransactionCommitsOrRollsBack() {
        val dir = newTestDir()
        val db = newTestSqlDbs(dir).openT(dir, 1, ArrayList())
        assertEquals(5, db.transaction { db.execute("INSERT INTO t(a) VALUES (1)"); db.transaction { 5 } })
        assertFailsWith<IllegalStateException> {
            db.transaction { db.execute("INSERT INTO t(a) VALUES (2)"); error("boom") }
        }
        assertEquals(1L, db.queryLong("SELECT COUNT(*) FROM t"))
        assertEquals(-1L, db.queryLong("SELECT a FROM t WHERE a = 99", default = -1L))
        db.close()
    }

    @Test fun readOnlyOpensAnExistingFileAndRefusesWrites() {
        val dir = newTestDir()
        val path = joinPath(dir, "t.db")
        newTestSqlDbs(dir).openT(dir, 1, ArrayList()).apply { execute("INSERT INTO t(c) VALUES ('kept')") }.close()
        val ro = newTestSqlDbs(dir).openReadOnly(path)
        var c: String? = null
        ro.query("SELECT c FROM t") { c = it.getString(0) }
        assertEquals("kept", c)
        assertFailsWith<Throwable> { ro.execute("INSERT INTO t(c) VALUES ('no')") }
        ro.close()
        assertFailsWith<Throwable> { newTestSqlDbs(dir).openReadOnly(joinPath(dir, "missing.db")) }
    }

    @Test fun aNameOpensInTheDatabaseFolder() {
        val dir = newTestDir()
        val made = ArrayList<String>()
        val db = testSqlDbsWithDirHook(dir) { made += it }.open("named.db", 1, onCreate = {}, onUpgrade = { _, _, _ -> })
        db.execute("CREATE TABLE x(a)")
        db.close()
        var n: String? = null
        newTestSqlDbs(dir).openReadOnly(joinPath(dir, "named.db")).apply { query("SELECT name FROM sqlite_master") { n = it.getString(0) } }.close()
        assertEquals("x", n)
        assertNull(made.firstOrNull { it != dir })
        assertTrue(made.isNotEmpty())
    }
}

/** [newTestSqlDbs] with a hook on the folder creation. */
expect fun testSqlDbsWithDirHook(dir: String, ensureDir: (String) -> Unit): SqlDbs
