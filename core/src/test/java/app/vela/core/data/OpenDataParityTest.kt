package app.vela.core.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.StringReader
import java.time.ZoneId
import kotlin.random.Random

/** The common NDW and fuel parsers against [NdwKxmlOracle] and [FuelGbOracle], the code they
 *  replaced: same records, same failures, same prices and day counts. */
class OpenDataParityTest {

    private fun record(id: String, status: String, start: String, end: String?, lat: String = "52.3731", extra: String = "") =
        """<sit:situation id="$id"><sit:situationRecord xsi:type="sit:GeneralNetworkManagement" id="${id}_01" note='a > b'>$extra
        <com:overallStartTime>$start</com:overallStartTime>${if (end != null) "<com:overallEndTime>$end</com:overallEndTime>" else ""}
        <loc:latitude>$lat</loc:latitude><loc:longitude>4.8922</loc:longitude>
        <sit:operatorActionStatus>$status</sit:operatorActionStatus>
        <sit:generalNetworkManagementType>bridgeSwingInOperation</sit:generalNetworkManagementType>
        </sit:situationRecord></sit:situation>"""

    private fun feed(body: String) = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <!-- NDW -->
        <mc:messageContainer xmlns:sit="s" xmlns:mc="m" xmlns:loc="l" xmlns:com="c" xmlns:xsi="x"><mc:payload>
        <com:publicationTime>2026-10-09T08:08:00.001119015Z</com:publicationTime><empty/><empty a="1" />
        $body
        </mc:payload></mc:messageContainer>"""

    private fun feeds(): List<String> {
        val r = Random(3)
        val statuses = listOf("approved", "implemented", "beingImplemented", "beingTerminated", "")
        val times = listOf("2026-10-09T09:23:00Z", "2026-10-09T08:05:12.5Z", "2026-10-09T08:05:12.123456789Z", "2026-10-09T09:23:00+02:00", "2026-10-09", "x")
        val generated = List(40) {
            feed((0 until r.nextInt(1, 6)).joinToString("\n") { i ->
                record(
                    "R$i", statuses.random(r), times.random(r), if (r.nextBoolean()) times.random(r) else null,
                    lat = listOf("52.3731", " 52.36 ", "5.2e1", "x", "").random(r),
                    extra = listOf("", "<!-- c -->", "<sit:x><![CDATA[a<b]]></sit:x>", "<sit:y>&amp;&#65;&#x42;</sit:y>").random(r),
                )
            })
        }
        return generated + listOf(
            feed(record("E", "approved", "2026-10-09T09:23:00Z", null).replace("<loc:latitude>52.3731", "<loc:latitude><![CDATA[52.3731]]>")),
            feed(record("F", "appr&#111;ved", "2026-10-09T09:23:00Z", null)),
            feed(record("G", "approved", "2026-10-09T09:23:00Z", null)).substringBeforeLast("</mc:payload>"),
            feed(record("H", "approved", "2026-10-09T09:23:00Z", null)).replace("</sit:situation>", "</sit:situatio>"),
            feed(record("I", "a&bogus;", "2026-10-09T09:23:00Z", null)),
            feed(record("J", "approved", "2026-10-09T09:23:00Z", null)).substringBefore("</sit:situationRecord>"),
            feed(record("K", "approved", "2026-10-09T09:23:00Z", null)).substringBefore("</sit:generalNetworkManagementType>"),
            "",
        )
    }

    @Test fun ndwFeedsParseAsKxml() {
        for (xml in feeds()) {
            val old = runCatching { NdwKxmlOracle.parse(xml.byteInputStream()) }
            val new = runCatching { NdwBridgeOpenings.parse(xml.encodeToByteArray()) }
            assertEquals(xml, old.isSuccess, new.isSuccess)
            assertEquals(xml, old.getOrNull(), new.getOrNull())
        }
    }

    @Test fun fuelFilesParseAsTheReader() {
        val sample = javaClass.getResourceAsStream("/fuel/fuel-gb-sample.csv")!!.bufferedReader().readText()
        val texts = listOf(
            sample, sample.replace("\n", "\r\n"), sample.replace("\n", "\r"), sample + "\n\n  \n", "", "\n", "brand,lat\n1,2",
            "BRAND , LAT,Lng,E10\nX,51.5,-0.1,172.94\n,91,0,1\nY,51.5,abc,1\nZ,51.5,-0.1,,\nW,-1,-1,0.004\n",
        )
        for (t in texts) {
            val old = FuelGbOracle.parse(StringReader(t))
            val new = FuelGb.parse(t)
            val show = { d: FuelGbStations -> listOf(d.lat.toList(), d.lng.toList(), d.brand.toList(), d.e10.toList(), d.e5.toList(), d.b7s.toList(), d.b7p.toList(), d.updated.toList()).toString() }
            assertEquals(t, show(old), show(new))
        }
    }

    @Test fun pricesAndDaysMatchTheJdk() {
        for (h in 0..400_000) assertEquals("$h", FuelGbOracle.formatPence(h), FuelGb.formatPence(h))
        val r = Random(4)
        val zones = listOf("UTC", "Europe/London", "America/Los_Angeles", "Asia/Kolkata", "Pacific/Chatham")
        repeat(50_000) {
            val now = r.nextLong(1_700_000_000L, 1_900_000_000L)
            val at = now - r.nextLong(-86_400L, 40 * 86_400L)
            val z = zones[it % zones.size]
            assertEquals("$at $now $z", FuelGbOracle.daysAgo(at, now, ZoneId.of(z)), FuelGb.daysAgo(at, now, kotlinx.datetime.TimeZone.of(z)))
        }
    }
}
