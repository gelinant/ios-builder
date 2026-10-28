package app.vela.ios.place

import app.vela.core.data.FuelGb
import app.vela.core.data.FuelGbStations
import app.vela.core.data.FuelGbStore
import app.vela.core.data.FuelPriceInfo
import app.vela.core.data.NearbyFuel
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.joinPath
import app.vela.ios.IosGraph

/**
 * UK Fuel Finder prices for the place sheet (SPEC 5.8, PLC-FUEL). The download and parse stay in
 * the common [FuelGbStore]; this file only supplies the process's platform graph and the icon
 * rule for open-data places, so the sheet gets the same file the map's fuel layer uses and asks
 * the network only when a UK gas station without a price is open.
 */
interface FuelStationSource {
    /** The forecourts in memory, downloading the file when needed; null while unavailable. */
    suspend fun load(): FuelGbStations?
}

private class GraphFuelStationSource(core: CoreGraph, now: () -> Long) : FuelStationSource {
    private val store = FuelGbStore(
        files = core.files,
        dir = { joinPath(core.files.noBackupDir, FuelGbStore.FOLDER) },
        http = core.http,
        nowMs = now,
    )

    override suspend fun load(): FuelGbStations? {
        store.ensure()
        return store.current?.takeIf { it.size > 0 }
    }
}

/** The sheet's fuel helpers, kept out of [PlaceStore]'s file so the facet stays readable. */
object PlaceFuel {
    /** The gas-station fallback for a place with no Google type: the map's own word rule, less
     *  categories that say "charg" (electric chargers share the fuel group on the map). */
    fun isFuelByCategory(place: Place): Boolean {
        val category = place.category?.lowercase() ?: return false
        if (category.contains("charg")) return false
        val words = category.split(NON_WORD).toSet()
        return ("gas" in words && "station" in words) ||
            "petrol" in words ||
            "fuel" in words ||
            "gasoline" in words ||
            "diesel" in words ||
            ("service" in words && "station" in words)
    }

    private val NON_WORD = Regex("[^\\p{L}]+")

    /** The process's source, null in tests that never started [IosGraph] or when the graph has no
     *  files or HTTP seam. One store per call site keeps the parsed file in memory. */
    fun source(now: () -> Long): FuelStationSource? =
        IosGraph.core?.let { GraphFuelStationSource(it, now) }

    /**
     * The UI-test place: a London forecourt with the card's fuel fields, or a shop closing in
     * 25 minutes. The screenshot scenario never downloads the real file.
     */
    fun fixture(kind: String, nowSec: Long): Pair<Place, FuelPriceInfo?>? {
        val at = LatLng(51.5074, -0.1278)
        return when (kind) {
            "fuel" -> {
                val updated = nowSec - 86_400
                val price = "172.9p/E10 · 199.9p/B7"
                Place(
                    id = "fixture:fuel",
                    name = "Vela Fuel Test",
                    location = at,
                    category = "Gas station",
                    address = "1 Test Street, London",
                    placeType = FuelGb.GAS_STATION_TYPE,
                    countryCode = FuelGb.FUEL_FINDER_COUNTRY,
                    fuelPrice = price,
                    fuelPriceAt = updated,
                ) to FuelPriceInfo(
                    price = price,
                    brand = "ESSO",
                    updatedAt = updated,
                    grade = "E10",
                    pence = 17_290,
                    nearby = NearbyFuel(brand = "TESCO", pence = 16_990, meters = 420.0),
                )
            }
            "closing" -> {
                val minute = (nowSec / 60 % 1_440).toInt()
                val closing = (minute + 25) % 1_440
                Place(
                    id = "fixture:closing",
                    name = "Vela Closing Test",
                    location = at,
                    category = "Cafe",
                    address = "2 Test Street, London",
                    statusText = "Open · Closes ${clock(closing)}",
                    openNow = true,
                ) to null
            }
            else -> null
        }
    }

    /** "305" to "5:05 PM", the same 12-hour shape Google writes in English-status locales. */
    private fun clock(minuteOfDay: Int): String {
        val h = minuteOfDay / 60
        val m = minuteOfDay % 60
        val mer = if (h < 12) "AM" else "PM"
        val h12 = when {
            h == 0 -> 12
            h > 12 -> h - 12
            else -> h
        }
        return if (m == 0) "$h12 $mer" else "$h12:${m.toString().padStart(2, '0')} $mer"
    }
}
