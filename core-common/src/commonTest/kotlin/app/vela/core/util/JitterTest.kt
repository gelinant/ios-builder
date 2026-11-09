package app.vela.core.util

import kotlin.test.AfterTest
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.Test
import kotlin.random.Random

class JitterTest {
    @AfterTest fun reset() { Jitter.random = Random.Default }

    @Test fun staysInsideTheSpread() {
        Jitter.random = Random(7)
        repeat(10_000) {
            val v = Jitter.around(120_000L)
            assertTrue(v in 90_000L..150_000L, "$v")
        }
    }

    @Test fun actuallySpreads() {
        Jitter.random = Random(7)
        val seen = (1..200).map { Jitter.around(120_000L) }.toSet()
        assertTrue(seen.size > 150)
    }

    @Test fun zeroSpreadIsExact() {
        assertEquals(700L, Jitter.around(700L, 0.0))
    }
}
