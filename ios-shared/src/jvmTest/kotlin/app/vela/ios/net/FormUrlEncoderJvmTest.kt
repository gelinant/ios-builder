package app.vela.ios.net

import app.vela.core.data.google.SearchPb
import app.vela.core.model.LatLng
import java.net.URLEncoder
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals

/** [FormUrlEncoder] against the JVM's own `URLEncoder`, which Android's search URLs go through. */
class FormUrlEncoderJvmTest {
    private fun check(s: String) = assertEquals(URLEncoder.encode(s, "UTF-8"), FormUrlEncoder.encode(s), "for <$s>")

    @Test fun searchPbMatches() {
        check(SearchPb.build("coffee", LatLng(37.7749, -122.4194), spanMeters = 4200.0))
        check(SearchPb.build("pho & ramen", LatLng(38.5449, -121.7405), offset = 20))
    }

    @Test fun randomStringsMatch() {
        val rnd = Random(7)
        val pool = (0x20..0x7e).map { it.toChar() } + listOf('é', 'ß', '日', '\u2615', '\u00a0', '\n', '\uD83D', '\uDE00', '\uDC00')
        repeat(2000) {
            check(String(CharArray(rnd.nextInt(0, 24)) { pool[rnd.nextInt(pool.size)] }))
        }
    }
}
