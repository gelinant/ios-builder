package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import kotlinx.datetime.TimeZone

/** UK Fuel Finder prices (SPEC 5.8) in the common source set: the parse, the match, the card's
 *  brand and age, and the nearby comparison. The Android JVM suite keeps the store and gzip
 *  coverage in `:core`; this one runs on both platforms. */
class FuelGbTest {
    private val now = 1_791_460_000L

    private val csv = """
        brand,lat,lng,e10,e5,b7s,b7p,updated
        ESSO,51.5074,-0.1278,172.9,,199.9,,1791454066
        TESCO,51.5076,-0.1278,169.9,,189.9,,1791454066
        BP,51.5100,-0.1200,175.0,,,,1791454066
        Shell Ltd,51.5200,-0.1000,,181.9,,,1786348800
        none,51.5074,-0.1200,175.0,174.0,,,1791454066
    """.trimIndent()

    private val data = FuelGb.parse(csv)
    private val esso = LatLng(51.5074, -0.1278)
    private val tesco = LatLng(51.5076, -0.1278)
    private val isFuel: (Place) -> Boolean = { it.category?.lowercase()?.contains("gas station") == true }

    private fun station(name: String, at: LatLng, category: String? = "Gas station", price: String? = null) =
        Place(id = "p:$name", name = name, location = at, category = category, fuelPrice = price)

    @Test fun parseReadsColumnsByNameAndSkipsBadRows() {
        val d = FuelGb.parse(
            """
            updated,lng,lat,brand,extra,e10
            1791454066,-0.1278,51.5074,ESSO,x,172.9
            1791454066,not-a-number,51.5,BP,x,170.9
            1791454066,-0.1278,51.5076,TESCO,x,
            """.trimIndent(),
        )
        assertEquals(2, d.size)
        assertEquals(17290, d.e10[0])
        assertEquals(-1, d.e10[1])
        assertEquals(-1, d.b7s[0])
        assertEquals(FuelGbStations.EMPTY.size, FuelGb.parse("").size)
        assertEquals(FuelGbStations.EMPTY.size, FuelGb.parse("nolat,nolng\n1,2\n").size)
    }

    @Test fun labelPetrolThenDiesel() {
        assertEquals("172.9p/E10 · 199.9p/B7", FuelGb.label(data, 0, now))
        assertEquals("175.0p/E10", FuelGb.label(data, 4, now))
        assertNull(FuelGb.label(data, 3, now))
    }

    @Test fun formatPenceKeepsThePumpsDecimal() {
        assertEquals("172.9", FuelGb.formatPence(17290))
        assertEquals("175.0", FuelGb.formatPence(17500))
        assertEquals("172.95", FuelGb.formatPence(17295))
    }

    @Test fun nearestAndBrandSlack() {
        assertEquals(0, FuelGb.pick(data, "Fuel stop", esso))
        assertEquals(1, FuelGb.pick(data, "Tesco Express", esso))
        assertEquals(0, FuelGb.pick(data, "Esso", tesco))
        assertNull(FuelGb.pick(data, "Fuel stop", LatLng(51.5050, -0.1278)))
        assertTrue(FuelGb.brandAgrees("SAINSBURYS", "Sainsbury's Petrol Station"))
        assertTrue(FuelGb.brandAgrees("EG ON THE MOVE", "EG On The Move Shell"))
        assertFalse(FuelGb.brandAgrees("Highland Fuels Ltd", "Shell Fuels"))
    }

    @Test fun infoAddsBrandAgeAndTheCheaperForecourtNearby() {
        val info = FuelGb.info(data, station("Esso", esso), now, isFuel)
        assertNotNull(info)
        assertEquals("172.9p/E10 · 199.9p/B7", info.price)
        assertEquals("ESSO", info.brand)
        assertEquals(1_791_454_066L, info.updatedAt)
        assertEquals("E10", info.grade)
        assertEquals(17290, info.pence)
        assertEquals("TESCO", info.nearby?.brand)
        assertEquals(16990, info.nearby?.pence)
        assertTrue((info.nearby?.meters ?: 0.0) < 50.0)
    }

    @Test fun nearbyShowsOnlyWhenItIsCheaperByAPennyAndWithinRange() {
        val close = FuelGb.parse("brand,lat,lng,e10,updated\nA,51.5074,-0.1278,172.9,1791454066\nB,51.5075,-0.1278,172.8,1791454066\n")
        assertNull(FuelGb.info(close, station("A", esso), now, isFuel)?.nearby)
        val cheaper = FuelGb.parse("brand,lat,lng,e10,updated\nA,51.5074,-0.1278,172.9,1791454066\nB,51.5075,-0.1278,171.9,1791454066\n")
        assertEquals("B", FuelGb.info(cheaper, station("A", esso), now, isFuel)?.nearby?.brand)
        val far = FuelGb.parse("brand,lat,lng,e10,updated\nA,51.5074,-0.1278,172.9,1791454066\nB,51.6000,-0.1278,160.0,1791454066\n")
        assertNull(FuelGb.info(far, station("A", esso), now, isFuel)?.nearby)
    }

    @Test fun googlePricesAndNonUkPlacesNeverGetFinderData() {
        val google = station("Esso", esso, price = "$5.34/Regular")
        assertNull(FuelGb.info(data, google, now, isFuel))
        val us = station("Esso", LatLng(38.5449, -121.7405))
        assertNull(FuelGb.info(data, us, now, isFuel))
        val cafe = station("Esso", esso, category = "Cafe")
        assertNull(FuelGb.info(data, cafe, now, isFuel))
        val ie = station("Esso", esso).copy(placeType = FuelGb.GAS_STATION_TYPE, countryCode = "IE")
        assertNull(FuelGb.info(data, ie, now, isFuel))
    }

    @Test fun staleFeedAndOldReportsShowNothing() {
        val p = station("Esso", esso)
        assertNotNull(FuelGb.info(data, p, now, isFuel))
        assertNull(FuelGb.info(data, p, data.newestReport + 3 * 86_400, isFuel))
        val old = FuelGb.parse(
            "brand,lat,lng,e10,updated\n" +
                "ESSO,51.50740,-0.12780,172.9,${now - 22 * 86_400}\n" +
                "BP,51.51000,-0.12000,175.0,$now\n",
        )
        assertNull(FuelGb.info(old, p, now, isFuel))
    }

    @Test fun annotateFillsOnlyUkGasStationsWithoutAPrice() {
        val p = station("Esso", esso)
        val filled = FuelGb.annotate(p, data, now, isFuel)
        assertEquals("172.9p/E10 · 199.9p/B7", filled.fuelPrice)
        assertEquals(1_791_454_066L, filled.fuelPriceAt)
        val google = station("Esso", esso, price = "$5.34/Regular")
        assertSame(google, FuelGb.annotate(google, data, now, isFuel))
        val us = station("Esso", LatLng(38.5449, -121.7405))
        assertSame(us, FuelGb.annotate(us, data, now, isFuel))
    }

    @Test fun irelandBoundaryCoversTheNorthOnly() {
        assertTrue(FuelGb.inUk(esso))
        assertTrue(FuelGb.inUk(LatLng(54.597, -5.930))) // Belfast
        assertTrue(FuelGb.inUk(LatLng(60.15, -1.15))) // Shetland
        assertFalse(FuelGb.inUk(LatLng(53.350, -6.260))) // Dublin
        assertFalse(FuelGb.inUk(LatLng(54.000, -6.400))) // Dundalk
        assertFalse(FuelGb.inUk(LatLng(48.8566, 2.3522)))
        assertFalse(FuelGb.inUk(LatLng(38.5449, -121.7405)))
    }

    @Test fun daysAgoCountsLocalCalendarDaysInTheGivenZone() {
        val utc = TimeZone.UTC
        val noon = 1_791_460_800L
        assertEquals(0, FuelGb.daysAgo(noon - 3_600, noon, utc))
        assertEquals(1, FuelGb.daysAgo(noon - 13 * 3_600, noon, utc))
        assertEquals(0, FuelGb.daysAgo(noon + 60, noon, utc))
        assertEquals(1, FuelGb.daysAgo(noon - 13 * 3_600, noon, "UTC"))
        assertEquals(1, FuelGb.daysAgo(noon - 13 * 3_600, noon, "Not/AZone"))
    }

    @Test fun freshFeedWindow() {
        assertTrue(FuelGb.fresh(data, data.newestReport + 2 * 86_400))
        assertFalse(FuelGb.fresh(data, data.newestReport + 2 * 86_400 + 1))
        assertFalse(FuelGb.fresh(FuelGbStations.EMPTY, now))
    }
}
