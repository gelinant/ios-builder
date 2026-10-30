package app.vela.core.data

import java.io.BufferedReader
import java.io.InputStream
import java.io.Reader
import java.util.Locale
import java.util.zip.GZIPInputStream

/** The CSV parse, price format and day count of [FuelGb] as they were before it moved to
 *  `:core-common` (readers, `String.format`, `java.time`), kept unchanged as the oracle of
 *  `FuelGbParityTest`. */
object FuelGbOracle {
    /** Whole local days from a report at [atSec] to [nowSec]: 0 today, 1 yesterday. */
    fun daysAgo(atSec: Long, nowSec: Long, zone: java.time.ZoneId): Int {
        val then = java.time.Instant.ofEpochSecond(atSec).atZone(zone).toLocalDate()
        val now = java.time.Instant.ofEpochSecond(nowSec).atZone(zone).toLocalDate()
        return java.time.temporal.ChronoUnit.DAYS.between(then, now).toInt().coerceAtLeast(0)
    }

    fun parseGzip(input: InputStream): FuelGbStations =
        GZIPInputStream(input, 1 shl 16).bufferedReader().use { parse(it) }

    /** Rows with a bad coordinate are skipped. A missing column reads as blank. */
    fun parse(reader: Reader): FuelGbStations {
        val br = reader as? BufferedReader ?: BufferedReader(reader)
        val header = br.readLine()?.split(',')?.map { it.trim().lowercase(Locale.ROOT) } ?: return FuelGbStations.EMPTY
        fun col(name: String) = header.indexOf(name)
        val cBrand = col("brand"); val cLat = col("lat"); val cLng = col("lng")
        val cE10 = col("e10"); val cE5 = col("e5"); val cB7s = col("b7s"); val cB7p = col("b7p")
        val cUpd = col("updated")
        if (cLat < 0 || cLng < 0) return FuelGbStations.EMPTY
        val lat = ArrayList<Double>(9000); val lng = ArrayList<Double>(9000); val brand = ArrayList<String>(9000)
        val e10 = ArrayList<Int>(9000); val e5 = ArrayList<Int>(9000); val b7s = ArrayList<Int>(9000)
        val b7p = ArrayList<Int>(9000); val upd = ArrayList<Long>(9000)
        val interned = HashMap<String, String>()
        while (true) {
            val line = br.readLine() ?: break
            if (line.isBlank()) continue
            val f = line.split(',')
            fun at(i: Int) = if (i in f.indices) f[i].trim() else ""
            val la = at(cLat).toDoubleOrNull() ?: continue
            val lo = at(cLng).toDoubleOrNull() ?: continue
            if (la !in -90.0..90.0 || lo !in -180.0..180.0) continue
            val b = at(cBrand)
            lat += la; lng += lo; brand += interned.getOrPut(b) { b }
            e10 += pence(at(cE10)); e5 += pence(at(cE5)); b7s += pence(at(cB7s)); b7p += pence(at(cB7p))
            upd += at(cUpd).toLongOrNull() ?: 0L
        }
        return FuelGbStations(
            lat.toDoubleArray(), lng.toDoubleArray(), brand.toTypedArray(),
            e10.toIntArray(), e5.toIntArray(), b7s.toIntArray(), b7p.toIntArray(), upd.toLongArray(),
        )
    }

    /** "172.9" -> 17290 (hundredths of a penny); blank or junk -> -1. */
    fun pence(s: String): Int {
        if (s.isEmpty()) return -1
        val v = s.toDoubleOrNull() ?: return -1
        return if (v > 0) Math.round(v * 100).toInt() else -1
    }

    /** 17290 -> "172.9", 17295 -> "172.95": one decimal as on the pumps, two only when present. */
    fun formatPence(hundredths: Int): String =
        if (hundredths % 10 == 0) String.format(Locale.US, "%.1f", hundredths / 100.0)
        else String.format(Locale.US, "%.2f", hundredths / 100.0)

}
