package app.vela.core.util

import kotlin.test.Test
import kotlin.test.assertEquals

/** Expected strings are what JDK 17 prints; `jvmTest` compares against the JDK at large. */
class FmtTest {
    @Test fun fixedRoundsTheShortestFormHalfUp() {
        assertEquals("0.13", Fmt.fixed(0.125, 2))
        assertEquals("3", Fmt.fixed(2.5, 0))
        assertEquals("-3", Fmt.fixed(-2.5, 0))
        assertEquals("-0.00000", Fmt.fixed(-0.0, 5))
        assertEquals("0.00001", Fmt.fixed(0.000005, 5))
        assertEquals("0.00000", Fmt.fixed(1e-7, 5))
        assertEquals("38.54491", Fmt.fixed(38.544905, 5))
        assertEquals("-121.74053", Fmt.fixed(-121.740525, 5))
        assertEquals("123456.78900", Fmt.fixed(123456.789, 5))
        assertEquals("10.00000", Fmt.fixed(9.999995, 5))
    }

    @Test fun mathRoundTiesUp() {
        assertEquals(3L, 2.5.mathRound())
        assertEquals(-2L, (-2.5).mathRound())
        assertEquals(0L, 0.49999999999999994.mathRound())
        assertEquals(0L, Double.NaN.mathRound())
    }

    @Test fun urlCodecMatchesTheJdk() {
        assertEquals("Caf%C3%A9+%C3%BC+%E6%9D%B1%E4%BA%AC+%F0%9F%98%80+a%2Bb*%7E", UrlCodec.encode("Café ü 東京 😀 a+b*~"))
        assertEquals("café 東!", UrlCodec.decode("caf%C3%A9+%E6%9D%B1%21"))
    }
}
