package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.platform.SqlDb
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.joinPath
import app.vela.core.platform.newTestDir
import app.vela.core.platform.newTestSqlDbs
import app.vela.core.util.OsmHours
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The offline stores read databases written the way the Android code wrote them before they moved
 * to [SqlDbs]: the `SQLiteOpenHelper` schema at version 2 with its `android_metadata` table, rows
 * in the `insertWithOnConflict` shape, and a region pack in the baker's normalized schema
 * (`scripts/poipack_build.py`).
 */
class OfflineStoresCompatTest {
    private val here = LatLng(38.5580, -121.7600)

    @AfterTest fun closePacks() = OfflinePacks.clear()

    /** A database as `SQLiteOpenHelper` left it after running [schema] at [version]. */
    private fun oldDb(sql: SqlDbs, dir: String, name: String, version: Int, schema: List<String>, rows: (SqlDb) -> Unit) {
        val db = sql.open(joinPath(dir, name), version, onCreate = { db ->
            db.execute("CREATE TABLE android_metadata (locale TEXT)")
            db.execute("INSERT INTO android_metadata VALUES ('en_US')")
            schema.forEach { db.execute(it) }
        }, onUpgrade = { _, _, _ -> })
        rows(db)
        db.close()
    }

    private val poiSchema = listOf(
        "CREATE TABLE poi(id TEXT PRIMARY KEY, name TEXT, lat REAL, lng REAL, category TEXT, " +
            "address TEXT, phone TEXT, website TEXT, hours TEXT)",
        "CREATE INDEX idx_poi_name ON poi(name COLLATE NOCASE)",
    )

    private fun oldPoi(db: SqlDb, id: String, name: String, lat: Double, lng: Double, cat: String?, addr: String?, hours: String?) =
        db.execute(
            "INSERT OR REPLACE INTO poi(website,phone,hours,address,category,lng,lat,name,id) VALUES (?,?,?,?,?,?,?,?,?)",
            listOf(null, "+1 530 555 0100", hours, addr, cat, lng, lat, name, id),
        )

    @Test fun thePoiStoreReadsAnOldDatabase() {
        val dir = newTestDir()
        val sql = newTestSqlDbs(dir)
        oldDb(sql, dir, "vela_offline_pois.db", 2, poiSchema) { db ->
            oldPoi(db, "osm:1", "Café Roma", 38.5582, -121.7601, "Cafe", "231 E St", "Mo-Fr 08:00-17:00")
            oldPoi(db, "osm:2", "McDonald's", 38.5600, -121.7550, "Fast food", null, null)
            oldPoi(db, "osm:3", "Pizza Far Away", 39.5, -121.0, "Restaurant", null, null)
        }
        val store = OfflinePoiStore(newTestSqlDbs(dir))
        assertEquals(3, store.count())
        val cafe = store.search("cafe", here)
        assertEquals("osm:1", cafe.first().id)
        assertEquals("Café Roma", cafe.first().name)
        assertEquals("+1 530 555 0100", cafe.first().phone)
        assertEquals(OsmHours.lines("Mo-Fr 08:00-17:00"), cafe.first().hours)
        assertEquals(listOf("osm:2"), store.search("mcdonalds", here).map { it.id })
        assertEquals(listOf("osm:1"), store.near(here, 60.0).map { it.id })
        // A new row goes in beside the old ones and replaces its own id.
        store.add(listOf(cafe.first().copy(name = "Cafe Roma Two")))
        assertEquals(3, store.count())
        assertEquals("Cafe Roma Two", store.search("roma", here).first().name)
    }

    @Test fun aVersionOneDatabaseIsRebuilt() {
        val dir = newTestDir()
        val sql = newTestSqlDbs(dir)
        oldDb(sql, dir, "vela_offline_pois.db", 1, listOf("CREATE TABLE poi(id TEXT PRIMARY KEY, name TEXT)")) { db ->
            db.execute("INSERT INTO poi(id,name) VALUES ('a','b')")
        }
        val store = OfflinePoiStore(newTestSqlDbs(dir))
        assertEquals(0, store.count())
    }

    private fun pack(sql: SqlDbs, dir: String): String {
        val path = joinPath(dir, "us-ca.db")
        val db = sql.open(path, 2, onCreate = { db ->
            listOf(
                "CREATE TABLE poi(id TEXT, name TEXT, lat REAL, lng REAL, category TEXT, address TEXT, phone TEXT, website TEXT, hours TEXT)",
                "CREATE TABLE streetname(sid INTEGER PRIMARY KEY, street TEXT, street_norm TEXT)",
                "CREATE TABLE addr(hn TEXT, sid INTEGER, city TEXT, lat REAL, lng REAL)",
                "CREATE TABLE streetpt(sid INTEGER, lat REAL, lng REAL)",
                "CREATE INDEX idx_streetname_norm ON streetname(street_norm)",
                "CREATE INDEX idx_addr_sid ON addr(sid)",
            ).forEach { db.execute(it) }
        }, onUpgrade = { _, _, _ -> })
        // A sid past 32 bits, as the baker's 63-bit hashes are.
        val sid = 7_000_000_000_123L
        db.execute("INSERT INTO streetname VALUES (?,?,?)", listOf(sid, "West Covell Boulevard", "west covell boulevard"))
        db.execute("INSERT INTO addr VALUES (?,?,?,?,?)", listOf("1451", sid, "Davis", 38.5581, -121.7601))
        db.execute("INSERT INTO addr VALUES (?,?,?,?,?)", listOf("1501", sid, "Davis", 38.5581, -121.7621))
        db.execute("INSERT INTO streetpt VALUES (?,?,?)", listOf(sid, 38.5579, -121.7610))
        db.execute(
            "INSERT INTO poi VALUES (?,?,?,?,?,?,?,?,?)",
            listOf("osm:9", "Covell Market", 38.5583, -121.7603, "Supermarket", "1451 West Covell Boulevard, Davis, CA 95616", null, null, null),
        )
        db.close()
        return path
    }

    @Test fun theAddressStoreReadsAnOldDatabaseAndAPack() {
        val dir = newTestDir()
        val sql = newTestSqlDbs(dir)
        oldDb(sql, dir, "vela_offline_addr.db", 2, listOf(
            "CREATE TABLE addr(id TEXT PRIMARY KEY, housenumber TEXT, street TEXT, street_norm TEXT, city TEXT, lat REAL, lng REAL)",
            "CREATE INDEX idx_addr_street ON addr(street_norm)",
            "CREATE INDEX idx_addr_hn ON addr(housenumber)",
            "CREATE TABLE street(id TEXT PRIMARY KEY, street TEXT, street_norm TEXT, lat REAL, lng REAL)",
            "CREATE INDEX idx_street_norm ON street(street_norm)",
        )) { db ->
            db.execute(
                "INSERT OR REPLACE INTO addr(lng,lat,city,street_norm,street,housenumber,id) VALUES (?,?,?,?,?,?,?)",
                listOf(-121.7500, 38.5500, "Davis", "east 8th street", "E 8th St", "500", "node/1"),
            )
            db.execute(
                "INSERT OR REPLACE INTO street(lng,lat,street_norm,street,id) VALUES (?,?,?,?,?)",
                listOf(-121.7450, 38.5450, "russell boulevard", "Russell Blvd", "russell boulevard@38.54500,-121.74500"),
            )
        }
        val packPath = pack(sql, dir)
        OfflinePacks.reload(sql, listOf(packPath, joinPath(dir, "missing.db")))
        assertEquals(1, OfflinePacks.dbs.size)
        val store = OfflineAddressStore(newTestSqlDbs(dir))
        assertEquals(1 + 2, store.count())
        assertEquals(1 + 1, store.streetCount())

        assertEquals(listOf("500 E 8th St"), store.geocode("500 E 8th Street", here).map { it.name })
        val pack = store.geocode("1451 W Covell Blvd", here)
        assertEquals(listOf("1451 West Covell Boulevard"), pack.map { it.name })
        assertEquals("addr:38.5581,-121.7601", pack.first().id)
        // 1475 lies between the two mapped numbers: an estimate on the pack's street.
        val between = store.geocode("1475 Covell Blvd", here).single()
        assertTrue(OfflineAddressStore.isApproximate(between))
        assertEquals("1475 West Covell Boulevard", between.name)
        // Only the centerline knows Russell Boulevard.
        assertEquals("Russell Blvd", store.geocode("Russell Blvd", here).single().name)

        assertEquals("1451 West Covell Boulevard, Davis", store.reverseGeocode(LatLng(38.5581, -121.7602)))
        assertEquals("Davis, CA 95616", store.localityNear(here))
        assertEquals("1451 West Covell Boulevard, Davis, CA 95616", store.completeAddress("1451 West Covell Boulevard", here))
    }
}
