package app.vela.core.util

import java.net.URLDecoder
import java.net.URLEncoder
import java.util.Locale
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** The common formatters against the JDK calls they replace. */
class JvmParityTest {
    private fun jdkFixed(v: Double, d: Int) = String.format(Locale.US, "%.${d}f", v)

    @Test fun fixedMatchesStringFormat() {
        val edge = listOf(
            0.0, -0.0, 0.5, 1.5, 2.5, -2.5, 0.125, 0.15, 0.000005, 0.0000049, 0.000006, -0.000001,
            9.999995, 99.999995, 999999.999995, 1e-7, 1e-20, 1e7, 1.2345e10, 1e300, Double.MIN_VALUE,
            Double.MAX_VALUE, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY,
            38.544905, 38.544915, -121.740525, 0.3, 40.0, 123456.0,
        )
        for (v in edge) for (d in 0..7) assertEquals(jdkFixed(v, d), Fmt.fixed(v, d), "$v at $d")
        val r = Random(42)
        repeat(200_000) {
            val v = when (it % 4) {
                0 -> r.nextDouble(-180.0, 180.0)
                1 -> Math.round(r.nextDouble(-90.0, 90.0) * 1e6) / 1e6 + 5e-6
                2 -> r.nextDouble(-1.0, 1.0) * Math.pow(10.0, r.nextInt(-8, 9).toDouble())
                else -> Math.round(r.nextDouble(-180.0, 180.0) * 1e5) / 1e5
            }
            val d = r.nextInt(0, 8)
            assertEquals(jdkFixed(v, d), Fmt.fixed(v, d), "$v at $d")
        }
    }

    @Test fun mathRoundMatchesTheJdk() {
        val vs = listOf(0.5, -0.5, 1.5, -1.5, 2.5, 0.49999999999999994, -0.49999999999999994,
            4503599627370497.0, 1e19, -1e19, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)
        for (v in vs) assertEquals(Math.round(v), v.mathRound(), "$v")
    }

    @Test fun encodeMatchesUrlEncoder() {
        val samples = listOf(
            "", "abc", "a b", "[out:json][timeout:25];node[\"highway\"=\"speed_camera\"](1,2,3,4);out body 4000;",
            "123 Main St, Davis", "Café ü ß 東京 😀", "a+b&c=d/e?f#g%h~i!j'k(l)m*n.-_",
            "\uD800", "x\uDC00y", "\uD83D", "\u0000\u007f\u0080\u07ff\u0800\uffff",
        )
        for (s in samples) assertEquals(URLEncoder.encode(s, "UTF-8"), UrlCodec.encode(s), s)
        val r = Random(7)
        repeat(20_000) {
            val s = String(CharArray(r.nextInt(0, 12)) { r.nextInt(0, 0x10000).toChar() })
            assertEquals(URLEncoder.encode(s, "UTF-8"), UrlCodec.encode(s))
        }
    }

    @Test fun decodeMatchesUrlDecoder() {
        val samples = listOf(
            "", "abc", "a+b", "%21%3F", "caf%C3%A9", "%E6%9D%B1%E4%BA%AC", "%F0%9F%98%80",
            "!11m2!2sAbC!3e", "%FF%FE", "%C3", "a%2Bb", "%+F", "%-0", "%ef%bc%a1",
        )
        for (s in samples) assertEquals(URLDecoder.decode(s, "UTF-8"), UrlCodec.decode(s), s)
        for (bad in listOf("%", "%4", "a%zz", "%-1", "%G0")) {
            assertFailsWith<IllegalArgumentException>(bad) { URLDecoder.decode(bad, "UTF-8") }
            assertFailsWith<IllegalArgumentException>(bad) { UrlCodec.decode(bad) }
        }
        val r = Random(9)
        repeat(20_000) {
            val s = String(CharArray(r.nextInt(0, 10)) { r.nextInt(0, 0x10000).toChar() })
            val enc = URLEncoder.encode(s, "UTF-8")
            assertEquals(URLDecoder.decode(enc, "UTF-8"), UrlCodec.decode(enc))
        }
    }
}
