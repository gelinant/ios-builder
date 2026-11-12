package app.vela.ios.search

import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.time.TimeSource

/**
 * The field's local budget, measured where the app's own ranking runs fast enough to prove it:
 * 300 saved places ranked in under 120 ms on the JVM. The Kotlin/Native debug simulator is an
 * order of magnitude slower and would test the compiler, not the product; the simulator UI run
 * checks the live `ulocal` value instead.
 */
class UnifiedRankingBudgetTest {
    @Test
    fun localRankingStaysUnderTheFieldBudget() {
        val pool = (0 until 300).map { index ->
            UnifiedHits.saved(
                id = "budget-$index", title = "Saved place $index", subtitle = "Saved",
                lat = 37.78, lng = -122.41, placeId = "budget-$index", featureId = null, listId = null)
        }
        UnifiedRanking.rank(pool, "warm")
        val samples = (0 until 5).map {
            val mark = TimeSource.Monotonic.markNow()
            val rows = UnifiedRanking.rank(pool, "saved place 5")
            assertTrue(rows.isNotEmpty())
            mark.elapsedNow().inWholeMilliseconds
        }.sorted()
        val median = samples[samples.size / 2]
        assertTrue(median < 120, "local ranking took ${median}ms")
    }
}
