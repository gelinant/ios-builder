package app.vela.core.util

import kotlin.math.PI
import kotlin.test.Test
import kotlin.test.assertEquals

/** The expected doubles are what JDK 17's `Math.toRadians` and `Math.toDegrees` print. */
class KmpTest {
    @Test fun toRadiansMatchesTheJdk() {
        assertEquals(0.6727354148519623, 38.5449.toRadians())
        assertEquals(-2.1247725580241568, (-121.7405).toRadians())
        assertEquals(PI, 180.0.toRadians())
        assertEquals(1.7453292519943295E-9, 1e-7.toRadians())
        assertEquals(6.283010774254387, 359.99.toRadians())
    }

    @Test fun toDegreesMatchesTheJdk() {
        assertEquals(38.54287087845048, 0.6727.toDegrees())
        assertEquals(-121.736342731446, (-2.1247).toDegrees())
        assertEquals(180.0, PI.toDegrees())
        assertEquals(5.7295779513082324E-8, 1e-9.toDegrees())
    }
}
