package app.vela.core.sat

import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * G-3: SGP4 propagation checked against the published verification element sets from AIAA
 * 2006-6753 (`SGP4-VER.TLE`). The reference TEME states come from the reference implementation
 * distributed with that paper; the three element sets here are near-Earth cases. The deep-space
 * cases live in [Sdp4Test], and this test also proves the automatic routing to SDP4.
 *
 * The acceptance is a position error below 1 km at a fixed epoch. The test also asserts the
 * stronger 0.1 km bound it actually measures, and checks the ECEF and geodetic conversion against
 * an independent geodetic position.
 */
class Sgp4Test {
    // AIAA 2006-6753 verification cases, WGS-72.
    private val vanguardText = """
        1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4753
        2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667
    """.trimIndent()

    private val deltaText = """
        1 06251U 62025E   06176.82412014  .00008885  00000-0  12808-3 0  3985
        2 06251  58.0579  54.0425 0030035 139.1568 221.1854 15.56387291  6774
    """.trimIndent()

    private val weatherText = """
        1 28057U 03049A   06177.78615833  .00000060  00000-0  35940-4 0  1836
        2 28057  98.4283 247.6961 0000884  88.1964 271.9322 14.35478080140550
    """.trimIndent()

    // A current near-Earth element set, used for the ECEF and geodetic check.
    private val issText = """
        ISS (ZARYA)
        1 25544U 98067A   26301.59601386  .00005724  00000+0  11161-3 0  9990
        2 25544  51.6336 359.9178 0006994 320.4528  39.5949 15.49090321592436
    """.trimIndent()

    private val geoText = """
        METEOSAT-9 (MSG-2)
        1 28912U 05049B   26301.91771722  .00000130  00000+0  00000+0 0  9990
        2 28912   9.6618  52.8151 0000854  37.1659 323.3913  1.00269021  8344
    """.trimIndent()

    // Perigee below the surface at epoch: SGP4's decayed flag must reject it, not draw it.
    private val decayedText = """
        1 99999U 58002B   26301.50000000  .00000023  00000-0  28098-4 0  4752
        2 99999  51.6336 348.7242 0500000 331.7664  19.3264 17.00000000 12349
    """.trimIndent()

    private fun state(text: String): TemeState =
        Sgp4.parseTles(text).single().let { tle ->
            assertNotNull(Sgp4.teme(tle, tle.epochMs), "no state at the element set epoch")
        }

    @Test fun matchesPublishedReferenceStates() {
        // Reference TEME states for minutes 0 and 120 after each element set epoch.
        val cases = listOf(
            Triple(vanguardText, 0.0, TemeState(
                7022.46529266, -1400.08296755, 0.03995155,
                1.89384101, 6.40589376, 4.53480725)),
            Triple(vanguardText, 120.0, TemeState(
                3440.26049598, -5392.71604108, -3130.05162672,
                6.77978421, 3.21944297, 3.07393470)),
            Triple(deltaText, 0.0, TemeState(
                3988.31022699, 5498.96657235, 0.90055879,
                -3.29003274, 2.35765282, 6.49662347)),
            Triple(deltaText, 120.0, TemeState(
                -3935.69800083, 409.10980837, 5471.33577327,
                -3.37478418, -6.63521104, -1.94205622)),
            Triple(weatherText, 0.0, TemeState(
                -2715.28237486, -6619.26436889, -0.01341443,
                -1.00858727, 0.42278200, 7.38527294)),
            Triple(weatherText, 120.0, TemeState(
                -1816.87920942, -1835.78762132, 6661.07926465,
                2.32514007, 6.65566933, 2.46339451)),
        )

        var worstPosition = 0.0
        var worstVelocity = 0.0
        for ((text, minutes, expected) in cases) {
            val tle = Sgp4.parseTles(text).single()
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

    @Test fun ecefAndGeodeticMatchTheIndependentPoint() {
        val tle = Sgp4.parseTles(issText).single()
        assertEquals("ISS (ZARYA)", tle.name)
        assertEquals(25544, tle.catalogNumber)
        assertEquals(2026, tle.epochYear)
        assertEquals(1.1161e-4, tle.bstar, 1e-12)
        assertEquals(92.96, tle.periodMinutes, 0.1)

        val at = 1_793_233_980_000L // 2026-10-29T00:33:00Z
        val fix = assertNotNull(Sgp4.fix(tle, at))
        // Reference geodetic point for the same element set and instant.
        assertEquals(-32.03, fix.latDeg, 0.2)
        assertEquals(161.70, fix.lonDeg, 0.2)
        assertEquals(430.0, fix.altitudeKm, 3.0)

        val ecefRadius = sqrt(
            fix.ecefXKm * fix.ecefXKm + fix.ecefYKm * fix.ecefYKm + fix.ecefZKm * fix.ecefZKm)
        val teme = assertNotNull(Sgp4.teme(tle, at))
        val temeRadius = sqrt(teme.xKm * teme.xKm + teme.yKm * teme.yKm + teme.zKm * teme.zKm)
        assertEquals(temeRadius, ecefRadius, 1e-6, "the rotation keeps the radius")
        assertTrue(fix.altitudeKm in 300.0..600.0)

        assertTrue(fix.speedKmS in 7.5..7.8, "orbital speed ${fix.speedKmS} km/s")
        val ecefSpeed = sqrt(
            fix.ecefVxKmS * fix.ecefVxKmS + fix.ecefVyKmS * fix.ecefVyKmS +
                fix.ecefVzKmS * fix.ecefVzKmS)
        assertTrue(ecefSpeed in 6.5..7.8, "ECEF speed $ecefSpeed km/s")
        assertTrue(abs(fix.latDeg) <= tle.inclinationDeg + 0.1,
            "the sub-point cannot exceed the inclination")
        assertTrue(hypot(fix.ecefXKm, fix.ecefYKm) < 7000.0)
    }

    @Test fun oldEpochIsRejected() {
        val tle = Sgp4.parseTles(issText).single()
        assertNull(Sgp4.teme(tle, tle.epochMs + 31L * 86_400_000L),
            "an element set older than 30 days is not drawn")
        assertNotNull(Sgp4.teme(tle, tle.epochMs + 29L * 86_400_000L))
    }

    @Test fun deepSpaceIsRoutedToSdp4AndDecayedOrbitsAreRejected() {
        val geo = Sgp4.parseTles(geoText).single()
        assertTrue(geo.periodMinutes >= 225.0)
        val fix = assertNotNull(Sgp4.fix(geo, geo.epochMs),
            "deep space is drawn by SDP4, not refused")
        assertTrue(fix.altitudeKm in 34_000.0..37_000.0, "GEO altitude ${fix.altitudeKm}")

        val decayed = Sgp4.parseTles(decayedText).single()
        assertNull(Sgp4.fix(decayed, decayed.epochMs), "a decayed orbit is never drawn")
    }

    @Test fun invalidElementSetIsSkipped() {
        // The line 1 checksum is wrong (last digit changed from 3 to 4).
        val broken = """
            1 00005U 58002B   00179.78495062  .00000023  00000-0  28098-4 0  4754
            2 00005  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667
        """.trimIndent()
        assertTrue(Sgp4.parseTles(broken).isEmpty())

        val truncated = """
            1 00005U 58002B   00179
            2 00005  34.2682
        """.trimIndent()
        assertTrue(Sgp4.parseTles(truncated).isEmpty())
    }

    private fun sqrt(value: Double): Double = kotlin.math.sqrt(value)
}
