package app.vela.core.offline

import app.vela.core.platform.SqlDbs
import app.vela.core.platform.newTestDir
import app.vela.core.platform.newTestSqlDbs
import app.vela.core.platform.queryLong
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** A place-pack delta applies in one transaction and rolls back when its counts do not match. */
class PackDeltaTest {
    private fun pack(sql: SqlDbs, dir: String): String {
        val path = "$dir/pack.db"
        val db = sql.open(path, 1, { d ->
            d.execute("CREATE TABLE poi(id TEXT, name TEXT, lat REAL, lng REAL, category TEXT, address TEXT, phone TEXT, website TEXT, hours TEXT)")
            d.execute("CREATE TABLE streetname(sid INTEGER PRIMARY KEY, street TEXT, street_norm TEXT)")
            d.execute("CREATE TABLE addr(hn TEXT, sid INTEGER, city TEXT, lat REAL, lng REAL)")
            d.execute("CREATE TABLE streetpt(sid INTEGER, lat REAL, lng REAL)")
            d.execute("INSERT INTO poi VALUES('a','Old cafe',43.7,7.4,'cafe',NULL,NULL,NULL,NULL)")
            d.execute("INSERT INTO streetname VALUES(1,'Rue A','rue a')")
            d.execute("INSERT INTO addr VALUES('1',1,'Monaco',43.7,7.4)")
            d.execute("INSERT INTO streetpt VALUES(1,43.7,7.4)")
        }, { _, _, _ -> })
        db.queryLong("PRAGMA user_version")
        db.close()
        return path
    }

    private fun delta(sql: SqlDbs, dir: String): String {
        val path = "$dir/delta.db"
        val db = sql.open(path, 1, { d ->
            for (table in PackDelta.TABLES.keys) {
                val cols = PackDelta.TABLES.getValue(table).joinToString(",")
                d.execute("CREATE TABLE del_$table ($cols)")
                d.execute("CREATE TABLE ins_$table ($cols)")
            }
            d.execute("DELETE FROM del_poi")
            d.execute("INSERT INTO del_poi VALUES('a','Old cafe',43.7,7.4,'cafe',NULL,NULL,NULL,NULL)")
            d.execute("INSERT INTO ins_poi VALUES('b','New cafe',43.71,7.41,'cafe',NULL,NULL,NULL,NULL)")
            d.execute("INSERT INTO ins_streetpt VALUES(1,43.72,7.42)")
        }, { _, _, _ -> })
        db.queryLong("PRAGMA user_version")
        db.close()
        return path
    }

    @Test fun applyingADeltaReplacesDeletedRowsAndVerifiesCounts() {
        val dir = newTestDir()
        val sql = newTestSqlDbs(dir)
        val pack = sql.open(pack(sql, dir), 1, {}, { _, _, _ -> })
        val delta = sql.openReadOnly(delta(sql, dir))
        val counts = mapOf("poi" to 1L, "streetname" to 1L, "addr" to 1L, "streetpt" to 2L)
        val outcome = PackDelta.apply(pack, delta, counts)
        assertTrue(outcome is PackDelta.Outcome.Applied, "$outcome")
        assertEquals(1, pack.queryLong("SELECT COUNT(*) FROM poi"))
        assertEquals(1, pack.queryLong("SELECT COUNT(*) FROM poi WHERE id='b'"))
        assertEquals(2, pack.queryLong("SELECT COUNT(*) FROM streetpt"))
        delta.close()
        pack.close()
    }

    @Test fun aCountMismatchRollsTheWholeApplyBack() {
        val dir = newTestDir()
        val sql = newTestSqlDbs(dir)
        val pack = sql.open(pack(sql, dir), 1, {}, { _, _, _ -> })
        val delta = sql.openReadOnly(delta(sql, dir))
        val outcome = PackDelta.apply(
            pack, delta, mapOf("poi" to 3L, "streetname" to 1L, "addr" to 1L, "streetpt" to 2L))
        assertTrue(outcome is PackDelta.Outcome.Refused, "$outcome")
        assertEquals(1, pack.queryLong("SELECT COUNT(*) FROM poi"))
        assertEquals(1, pack.queryLong("SELECT COUNT(*) FROM poi WHERE id='a'"))
        assertEquals(1, pack.queryLong("SELECT COUNT(*) FROM streetpt"))
        delta.close()
        pack.close()
    }
}
