package app.vela.ios.world

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Digitraffic GeoJSON, AISHub XML and JSON, the MMSI merge, the 500 ship cap and the five
 *  minute cache, all without a network. */
class MaritimeStoreTest {
    private val box = MaritimeBox(south = 59.0, west = 20.0, north = 61.0, east = 26.0)
    private val now = 1_790_000_000_000L

    private val digitrafficLocations = """
        {
          "type": "FeatureCollection",
          "dataUpdatedTime": "2026-10-28T11:38:52Z",
          "features": [
            {
              "mmsi": 230713000,
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [23.607103, 59.487802] },
              "properties": {
                "mmsi": 230713000, "sog": 7.9, "cog": 246.0, "navStat": 0,
                "heading": 243, "timestamp": 49,
                "timestampExternal": 1790000000000
              }
            },
            {
              "mmsi": 276835000,
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [24.703138, 59.457528] },
              "properties": {
                "mmsi": 276835000, "sog": 0.0, "cog": 19.9,
                "timestampExternal": 1790000600000
              }
            },
            {
              "mmsi": 111111111,
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [25.0, 60.1] },
              "properties": { "mmsi": 111111111, "sog": 12.5, "cog": 90.0 }
            },
            {
              "mmsi": 222222222,
              "type": "Feature",
              "geometry": null,
              "properties": { "mmsi": 222222222, "sog": 1.0, "cog": 1.0 }
            }
          ]
        }
    """.trimIndent()

    private val digitrafficVessels = """
        [
          { "mmsi": 230713000, "name": "AUGUSTA", "shipType": 70 },
          { "mmsi": 276835000, "name": "TANKER ONE", "shipType": 80 },
          { "mmsi": 111111111, "name": "", "shipType": 0 }
        ]
    """.trimIndent()

    private val aishubXml = """
        <?xml version="1.0" encoding="iso-8859-1"?>
        <VESSELS>
          <ERROR>false</ERROR>
          <USERNAME>member</USERNAME>
          <FORMAT>XML</FORMAT>
          <RECORDS>2</RECORDS>
          <SHIP>
            <MMSI>230713000</MMSI>
            <TIME>2026-10-27 11:52:13 GMT</TIME>
            <LATITUDE>59.5100</LATITUDE>
            <LONGITUDE>23.6100</LONGITUDE>
            <COG>246.0</COG>
            <SOG>7.9</SOG>
            <TYPE>70</TYPE>
            <NAME>AUGUSTA</NAME>
          </SHIP>
          <SHIP>
            <MMSI>999999999</MMSI>
            <TIME>2026-10-27 11:52:13 GMT</TIME>
            <LATITUDE></LATITUDE>
            <LONGITUDE></LONGITUDE>
            <NAME>NO POSITION</NAME>
          </SHIP>
        </VESSELS>
    """.trimIndent()

    private val aishubJson = """
        [
          {"ERROR": false, "USERNAME": "member", "FORMAT": "JSON", "VERSION": "1.0",
           "RECORDS": 1},
          [
            {"MMSI": "276835000", "TIME": "2026-10-27 11:52:13 GMT",
             "LONGITUDE": "24.703138", "LATITUDE": "59.457528",
             "COG": "20", "SOG": "0", "HEADING": "511", "TYPE": "80",
             "NAME": "TANKER ONE"}
          ]
        ]
    """.trimIndent()

    @Test fun digitrafficGeoJsonKeepsPositionCourseSpeedAndType() {
        val meta = DigitrafficSource.parseVessels(digitrafficVessels)
        val ships = DigitrafficSource.parseLocations(digitrafficLocations, meta)
        assertEquals(3, ships.size, "a feature without geometry is dropped")
        val augusta = ships.first { it.mmsi == "230713000" }
        assertEquals(59.487802, augusta.lat)
        assertEquals(23.607103, augusta.lng)
        assertEquals(7.9, augusta.speedKnots)
        assertEquals(246.0, augusta.courseDeg)
        assertEquals("Cargo", augusta.typeLabel)
        assertEquals("AUGUSTA", augusta.title)
        assertTrue(augusta.detail.contains("MMSI 230713000"))
        assertTrue(augusta.detail.contains("course 246°"))

        val unknown = ships.first { it.mmsi == "111111111" }
        assertEquals("Type unknown", unknown.typeLabel, "no type is never invented")
        assertEquals("MMSI 111111111", unknown.title, "an empty name falls back to the MMSI")
        assertEquals(0L, unknown.updatedAtMs)
    }

    @Test fun digitrafficUrlCarriesTheBox() {
        val url = DigitrafficSource.locationsUrl(box)
        assertTrue(url.contains("south=5900000"))
        assertTrue(url.contains("north=6100000"))
        assertTrue(url.contains("west=2000000"))
        assertTrue(url.contains("east=2600000"))
    }

    @Test fun aishubXmlReadsShipsAndDropsOneWithoutPosition() {
        val answer = AishubSource.parseXml(aishubXml)
        val ships = (answer as AisAnswer.Ships).list
        assertEquals(1, ships.size)
        val augusta = ships.single()
        assertEquals("230713000", augusta.mmsi)
        assertEquals("aishub", augusta.source)
        assertEquals("Cargo", augusta.typeLabel)
        assertTrue(augusta.updatedAtMs > 0, "the AISHub GMT time is parsed")
    }

    @Test fun aishubRequestUrlUsesTheDocumentedFormatAndTheBox() {
        val url = AishubSource.requestUrl(box, "member-key")
        assertTrue(url.contains("format=1"))
        assertTrue(url.contains("output=json"))
        assertTrue(url.contains("latmin=5900000"))
        assertTrue(url.contains("latmax=6100000"))
        assertTrue(url.contains("lonmin=2000000"))
        assertTrue(url.contains("lonmax=2600000"))
        assertTrue(url.contains("username=member-key"))
    }

    @Test fun aishubJsonReadsShips() {
        val answer = AishubSource.parseJson(aishubJson)
        val ships = (answer as AisAnswer.Ships).list
        assertEquals(1, ships.size)
        assertEquals("TANKER ONE", ships.single().title)
        assertEquals("Tanker", ships.single().typeLabel)
    }

    @Test fun aishubRefusedKeyIsReportedNotHidden() {
        val answer = AishubSource.parse(
            """
            <?xml version="1.0" encoding="iso-8859-1"?>
            <VESSELS ERROR="true" FORMAT="AIS">
              <ERROR_MESSAGE>Invalid username or password!</ERROR_MESSAGE>
            </VESSELS>
            """.trimIndent().encodeToByteArray())
        assertTrue(answer is AisAnswer.KeyRejected)
        assertTrue((answer as AisAnswer.KeyRejected).message.contains("Invalid username"))
        assertEquals("%20", AishubSource.percentEncode(" "))
    }

    @Test fun dedupKeepsTheFresherPositionForTheSameMmsi() = runTest {
        val stale = ship("230713000", 59.40, 23.10, at = now - 120_000)
        val fresh = ship("230713000", 59.48, 23.60, at = now - 10_000, source = "aishub")
        val store = MaritimeStore(
            digitraffic = FakeSource(AisAnswer.Ships(listOf(stale))),
            aishub = FakeSource(AisAnswer.Ships(listOf(fresh))),
            now = { now })
        val snapshot = assertNotNull(store.refresh(box, "member-key"))
        assertEquals(1, snapshot.ships.size)
        assertEquals(23.60, snapshot.ships.single().lng, "the fresher AISHub position wins")
        assertEquals("aishub", snapshot.ships.single().source)
        assertEquals(MaritimeStore.COVERAGE_BOTH, snapshot.coverage)
    }

    @Test fun dedupKeepsTheFresherDigitrafficPosition() = runTest {
        val fresh = ship("230713000", 59.40, 23.10, at = now - 5_000)
        val stale = ship("230713000", 59.48, 23.60, at = now - 90_000, source = "aishub")
        val store = MaritimeStore(
            digitraffic = FakeSource(AisAnswer.Ships(listOf(fresh))),
            aishub = FakeSource(AisAnswer.Ships(listOf(stale))),
            now = { now })
        val snapshot = assertNotNull(store.refresh(box, "member-key"))
        assertEquals(23.10, snapshot.ships.single().lng)
        assertEquals("digitraffic", snapshot.ships.single().source)
    }

    @Test fun capKeepsTheFiveHundredNearestShips() = runTest {
        val ships = (0..500).map { index ->
            ship("2${index.toString().padStart(8, '0')}", 59.0 + index * 0.001, 24.0, at = now)
        }
        val largeBox = MaritimeBox(south = 58.0, west = 22.0, north = 70.0, east = 26.0)
        val store = MaritimeStore(
            digitraffic = FakeSource(AisAnswer.Ships(ships)),
            aishub = FakeSource(AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED)),
            now = { now })
        val snapshot = assertNotNull(store.refresh(largeBox, null))
        assertEquals(500, snapshot.ships.size)
        assertTrue(snapshot.ships.none { it.mmsi == "200000000" },
            "the ship farthest from the view center is the one dropped")
        assertEquals(500, snapshot.rows.count { it.id.startsWith("maritime-ship-") })
    }

    @Test fun fiveMinuteCacheSkipsBothSources() = runTest {
        var clock = now
        val digitraffic = FakeSource(AisAnswer.Ships(listOf(ship("230713000", 59.4, 23.6, now))))
        val aishub = FakeSource(AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED))
        val store = MaritimeStore(digitraffic, aishub, now = { clock })
        assertNotNull(store.refresh(box, null))
        assertEquals(1, digitraffic.calls)
        assertNotNull(store.refresh(box, null))
        assertEquals(1, digitraffic.calls, "a second call inside five minutes uses the cache")

        clock = now + 4 * 60_000L + 59_000L
        assertNotNull(store.refresh(box, null))
        assertEquals(1, digitraffic.calls)

        clock = now + 5 * 60_000L + 1_000L
        assertNotNull(store.refresh(box, null))
        assertEquals(2, digitraffic.calls, "the cache expires after five minutes")
    }

    @Test fun movingOutsideTheCachedBoxRefetches() = runTest {
        var clock = now
        val digitraffic = FakeSource(AisAnswer.Ships(listOf(ship("230713000", 59.4, 23.6, now))))
        val store = MaritimeStore(
            digitraffic,
            FakeSource(AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED)),
            now = { clock })
        assertNotNull(store.refresh(box, null))
        val far = MaritimeBox(south = 35.0, west = 24.0, north = 37.0, east = 26.0)
        val outside = assertNotNull(store.refresh(far, null))
        assertEquals(2, digitraffic.calls, "a view outside the cached box asks again")
        assertEquals(MaritimeStore.COVERAGE_FINLAND, outside.coverage)
    }

    @Test fun noKeySaysKeyRequiredAndKeepsFinlandOnly() = runTest {
        val store = MaritimeStore(
            digitraffic = FakeSource(AisAnswer.Ships(listOf(ship("230713000", 59.4, 23.6, now)))),
            aishub = FakeSource(AisAnswer.Ships(emptyList())),
            now = { now })
        val snapshot = assertNotNull(store.refresh(box, null))
        assertEquals(MaritimeStore.AISHUB_KEY_REQUIRED, snapshot.aishub)
        assertEquals(MaritimeStore.COVERAGE_FINLAND, snapshot.coverage)
        val keyRow = snapshot.rows.first { it.id == "maritime-aishub" }
        assertTrue(keyRow.title.contains("key required"))
        assertTrue(snapshot.rows.first { it.id == "maritime-coverage" }
            .detail.contains("Not for navigation"))
    }

    @Test fun rejectedKeyKeepsDigitrafficShipsAndSaysSo() = runTest {
        val store = MaritimeStore(
            digitraffic = FakeSource(AisAnswer.Ships(listOf(ship("230713000", 59.4, 23.6, now)))),
            aishub = FakeSource(AisAnswer.KeyRejected("Invalid username or password!")),
            now = { now })
        val snapshot = assertNotNull(store.refresh(box, "bad-key"))
        assertEquals(MaritimeStore.AISHUB_REJECTED, snapshot.aishub)
        assertEquals(1, snapshot.ships.size)
        assertTrue(snapshot.rows.first { it.id == "maritime-aishub" }
            .title.contains("key rejected"))
    }

    @Test fun outsideFinlandAsksNothingAndStillExplains() = runTest {
        val digitraffic = FakeSource(AisAnswer.OutsideCoverage)
        val store = MaritimeStore(
            digitraffic, FakeSource(AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED)),
            now = { now })
        val greek = MaritimeBox(south = 35.0, west = 24.0, north = 37.0, east = 26.0)
        val snapshot = assertNotNull(store.refresh(greek, null))
        assertEquals(MaritimeStore.COVERAGE_OUTSIDE, snapshot.coverage)
        assertEquals(0, snapshot.ships.size)
        assertTrue(snapshot.rows.first { it.id == "maritime-coverage" }
            .title.contains("Finland only"))
        assertTrue(snapshot.rows.any { it.id == "maritime-aishub" })
        assertEquals(1, digitraffic.calls)
        assertNotNull(store.refresh(greek, null))
        assertEquals(1, digitraffic.calls, "an outside view is cached too, no request loop")
    }

    @Test fun bothSourcesDownKeepsThePreviousSnapshot() = runTest {
        var down = false
        var clock = now
        val store = MaritimeStore(
            digitraffic = FakeSource(
                if (down) AisAnswer.Failed
                else AisAnswer.Ships(listOf(ship("230713000", 59.4, 23.6, now)))),
            aishub = FakeSource(AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED)),
            now = { clock })
        val first = assertNotNull(store.refresh(box, null))
        down = true
        clock = now + 6 * 60_000L
        val second = assertNotNull(store.refresh(box, null))
        assertEquals(first.rows, second.rows)
        assertEquals(1, second.ships.size)
    }

    @Test fun firstRefreshWithBothSourcesDownIsUnavailableNotEmpty() = runTest {
        val store = MaritimeStore(
            digitraffic = FakeSource(AisAnswer.Failed),
            aishub = FakeSource(AisAnswer.KeyRequired(AishubSource.KEY_REQUIRED)),
            now = { now })
        assertNull(store.refresh(box, null), "the host shows unavailable, not an empty sea")
    }

    private fun ship(
        mmsi: String,
        lat: Double,
        lng: Double,
        at: Long,
        source: String = "digitraffic",
    ) = AisShip(
        mmsi = mmsi, lat = lat, lng = lng, courseDeg = 90.0, speedKnots = 8.0,
        shipType = 70, name = "SHIP $mmsi", updatedAtMs = at, source = source)

    private class FakeSource(private val answer: AisAnswer) : AisSource {
        var calls = 0
            private set

        override suspend fun fetch(box: MaritimeBox, key: String?): AisAnswer {
            calls++
            return answer
        }
    }
}
