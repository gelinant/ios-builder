package app.vela.core.data

import java.math.BigInteger
import kotlin.test.Test
import kotlin.test.assertEquals

/** The import readers give what their `java.math` and `String.format` code gave on Android. */
class ImportJvmParityTest {
    @Test
    fun `a cid converts to hex as BigInteger does`() {
        val cases = listOf(
            "0", "7", "007", "15", "16", "255", "-0", "-255", "+42", "9223372036854775807",
            "18446744073709551615", "18446744073709551616", "123456789012345678901234567890",
            "12345678901234567890", "١٢٣", "", "+", "-", "12a", " 1", "1.5",
        )
        for (s in cases) {
            val jvm = runCatching { BigInteger(s) }.getOrNull()?.toString(16)?.lowercase()
            assertEquals(jvm, TakeoutCsv.decimalToHex(s), "cid '$s'")
        }
    }

    @Test
    fun `an imported pin keeps its id and label`() {
        val p = PlaceImport.parse("""<gpx><wpt lat="38.544905" lon="-121.740516"></wpt></gpx>""").single()
        assertEquals("imp:" + "%.5f,%.5f".format(java.util.Locale.US, 38.544905, -121.740516), p.id)
        assertEquals("%.4f, %.4f".format(java.util.Locale.US, 38.544905, -121.740516), p.name)
        val link = MapLink(lat = 38.5449065, lng = -121.7405167)
        assertEquals(String.format(java.util.Locale.US, "%.5f, %.5f", 38.5449065, -121.7405167), link.label)
    }
}
