package app.vela.core.sat

import kotlin.math.max
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * SDP4 checked against three published deep-space verification element sets from AIAA 2006-6753
 * (`SGP4-VER.TLE`): two 12-hour resonant Molniya objects (08195 and 09880) and one 24-hour
 * resonant geostationary object (24208). The reference TEME states come from the reference
 * implementation's `tcppver.out`, at the element set epoch and 120 minutes later.
 *
 * The acceptance is a position error below 1 km and a velocity error below 0.01 km/s; the test
 * also asserts the stricter bound it measures.
 */
class Sdp4Test {
    private val molniya1 = """
        1 08195U 75081A   06176.33215444  .00000099  00000-0  11873-3 0   813
        2 08195  64.1586 279.0717 6877146 264.7651  20.2257  2.00491383225656
    """.trimIndent()

    private val molniya2 = """
        1 09880U 77021A   06176.56157475  .00000421  00000-0  10000-3 0  9814
        2 09880  64.5968 349.3786 7069051 270.0229  16.3320  2.00813614112380
    """.trimIndent()

    private val geostationary = """
        1 24208U 96044A   06177.04061740 -.00000094  00000-0  10000-3 0  1600
        2 24208   3.8536  80.0121 0026640 311.0977  48.3000  1.00778054 36119
    """.trimIndent()

    @Test fun matchesPublishedDeepSpaceReferenceStates() {
        val cases = listOf(
            Triple(molniya1, 0.0, TemeState(
                2349.89483350, -14785.93811562, 0.02119378,
                2.721488096, -3.256811655, 4.498416672)),
            Triple(molniya1, 120.0, TemeState(
                15223.91713658, -17852.95881713, 25280.39558224,
                1.079041732, 0.875187372, 2.485682813)),
            Triple(molniya2, 0.0, TemeState(
                13020.06750784, -2449.07193500, 1.15896030,
                4.247363935, 1.597178501, 4.956708611)),
            Triple(molniya2, 120.0, TemeState(
                19190.32482476, 9249.01266902, 26596.71345328,
                -0.624960193, 1.324550562, 2.495697637)),
            Triple(geostationary, 0.0, TemeState(
                7534.10987189, 41266.39266843, -0.10801028,
                -3.027168008, 0.558848996, 0.207982755)),
            Triple(geostationary, 120.0, TemeState(
                -14289.19940414, 39469.05530051, 1428.62838591,
                -2.893205245, -1.045447840, 0.179634249)),
        )

        var worstPosition = 0.0
        var worstVelocity = 0.0
        for ((text, minutes, expected) in cases) {
            val tle = Sgp4.parseTles(text).single()
            assertTrue(tle.isDeepSpace, "${tle.catalogNumber} is a deep-space element set")
            val at = tle.epochMs + (minutes * 60_000.0).toLong()
            val actual = assertNotNull(Sgp4.teme(tle, at), "${tle.catalogNumber} at $minutes min")
            val positionError = sqrt(
                (actual.xKm - expected.xKm) * (actual.xKm - expected.xKm) +
                    (actual.yKm - expected.yKm) * (actual.yKm - expected.yKm) +
                    (actual.zKm - expected.zKm) * (actual.zKm - expected.zKm))
            val velocityError = sqrt(
                (actual.vxKmS - expected.vxKmS) * (actual.vxKmS - expected.vxKmS) +
                    (actual.vyKmS - expected.vyKmS) * (actual.vyKmS - expected.vyKmS) +
                    (actual.vzKmS - expected.vzKmS) * (actual.vzKmS - expected.vzKmS))
            worstPosition = max(worstPosition, positionError)
            worstVelocity = max(worstVelocity, velocityError)
            assertTrue(positionError < 1.0,
                "${tle.catalogNumber} at $minutes min is $positionError km off")
            assertTrue(velocityError < 0.01,
                "${tle.catalogNumber} at $minutes min is $velocityError km/s off")
        }
        assertTrue(worstPosition < 0.1, "measured position error $worstPosition km")
        assertTrue(worstVelocity < 0.001, "measured velocity error $worstVelocity km/s")
    }

    @Test fun geostationaryStaysOverItsLongitude() {
        val tle = Sgp4.parseTles(geostationary).single()
        val first = assertNotNull(Sgp4.fix(tle, tle.epochMs))
        assertTrue(first.altitudeKm in 34_000.0..37_000.0, "GEO altitude ${first.altitudeKm}")

        // One sidereal day later the sub-point is within a few degrees of the first one. This
        // element set is not exactly synchronous, so a small drift is expected.
        val next = assertNotNull(Sgp4.fix(tle, tle.epochMs + 86_164_000L))
        var deltaLon = kotlin.math.abs(next.lonDeg - first.lonDeg)
        if (deltaLon > 180.0) deltaLon = 360.0 - deltaLon
        assertTrue(deltaLon < 5.0, "GEO drifted ${deltaLon} deg in a day")
    }

    @Test fun nearEarthElementSetKeepsUsingSgp4() {
        val vanguard = """
            1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753
            2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667
        """.trimIndent()
        val tle = Sgp4.parseTles(vanguard).single()
        assertTrue(!tle.isDeepSpace)
        val state = assertNotNull(Sgp4.teme(tle, tle.epochMs))
        assertTrue(sqrt(state.xKm * state.xKm + state.yKm * state.yKm +
            state.zKm * state.zKm) in 6000.0..9000.0)
    }
}
