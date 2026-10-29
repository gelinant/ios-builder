package app.vela.core.data

import java.text.Normalizer
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

/** The offline search code against the JDK calls it used before it moved to common. */
class OfflineRankJvmParityTest {
    private val accented = Regex("[\u00C0-\u024F\u1EA0-\u1EF9]")
    private val marks = Regex("([A-Za-z\u00C0-\u024F])\\p{Mn}+")

    /** `OfflineRank.fold` as it was, over `java.text.Normalizer`. */
    private fun oldFold(s: String): String =
        marks.replace(accented.replace(s) { Normalizer.normalize(it.value, Normalizer.Form.NFD) }, "$1").lowercase()
            .replace("ß", "ss").replace("æ", "ae").replace("œ", "oe").replace("ø", "o").replace("ł", "l").replace("đ", "d").replace("ı", "i")
            .replace("'", "").replace("\u2019", "").replace(".", "").replace('-', ' ')

    @Test fun theDecompositionTableIsTheJdks() {
        for (cp in (0x00C0..0x024F) + (0x1EA0..0x1EF9)) {
            val c = cp.toChar()
            val jdk = Normalizer.normalize(c.toString(), Normalizer.Form.NFD)
            assertEquals(jdk, OfflineRank.LATIN_NFD[c] ?: c.toString(), "U+%04X".format(cp))
            assertEquals(oldFold(c.toString()), OfflineRank.fold(c.toString()), "fold U+%04X".format(cp))
        }
        for (s in listOf("Café Central", "Hauptstraße", "Łódź", "Phở Hòa", "İstanbul", "Cafe\u0301", "Ǟ\u0301x", "Музей", "ガソリン", "St. Hubert's")) {
            assertEquals(oldFold(s), OfflineRank.fold(s), s)
        }
    }

    @Test fun streetIdsKeepTheDefaultLocaleFormat() {
        val was = Locale.getDefault()
        try {
            for (loc in listOf(Locale.US, Locale.FRANCE, Locale("ar", "EG"))) {
                Locale.setDefault(loc)
                val p = OfflineAddressStore.StreetPt("W Covell Blvd", 38.558049, -121.7600051)
                val old = "${OfflineAddressStore.normalizeStreet(p.street)}@${"%.5f".format(p.lat)},${"%.5f".format(p.lng)}"
                assertEquals(old, OfflineAddressStore.streetId(p), loc.toString())
            }
        } finally {
            Locale.setDefault(was)
        }
    }
}
