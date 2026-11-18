package app.vela.core.net

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** SET-PRIVACY: the Google request counter keeps an exact host, survives a relaunch and clears. */
class GoogleRequestCounterTest {
    private val day = "2026-10-27"

    @Test fun `counts per Google host and per purpose only`() {
        GoogleRequestCounter.clear()
        GoogleRequestCounter.recordSentUrl("https://www.google.com/search?tbm=map&q=x", null, day)
        GoogleRequestCounter.recordSentUrl("https://www.google.com/search?tbm=map&q=y", null, day)
        GoogleRequestCounter.recordSentUrl("https://lh3.googleusercontent.com/p/abc", null, day)
        GoogleRequestCounter.recordSentUrl("https://photon.komoot.io/api?q=x", null, day)
        GoogleRequestCounter.recordSentUrl("https://notgoogle.com/search", null, day)
        GoogleRequestCounter.recordBlockedUrl("https://maps.googleapis.com/maps/api/js", day)
        GoogleRequestCounter.recordBlockedUrl("https://example.com/", day)

        val usage = GoogleRequestCounter.snapshot()[day]!!
        assertEquals(mapOf("lh3.googleusercontent.com" to 1, "www.google.com" to 2), usage.sent)
        assertEquals(mapOf("images" to 1, "search" to 2), usage.kinds)
        assertEquals(mapOf("maps.googleapis.com" to 1), usage.blocked)
        assertEquals(3, GoogleRequestCounter.totalTodayForTest(day))
        GoogleRequestCounter.clear()
    }

    @Test fun `a saved counter restores per host after a relaunch`() {
        GoogleRequestCounter.clear()
        GoogleRequestCounter.recordSentHost("www.google.com", "search", day)
        GoogleRequestCounter.recordSentHost("www.google.com", "search", day)
        GoogleRequestCounter.recordSentHost("maps.googleapis.com", "directions", day)
        GoogleRequestCounter.recordBlockedHost("play.google.com", day)
        val saved = GoogleRequestCounter.save()
        assertTrue(saved.contains(day))

        // A new process: the object is cold until the app reads its store.
        GoogleRequestCounter.clear()
        assertEquals(0, GoogleRequestCounter.snapshot().size)
        GoogleRequestCounter.restore(saved)
        val usage = GoogleRequestCounter.snapshot()[day]!!
        assertEquals(2, usage.sent["www.google.com"])
        assertEquals(1, usage.sent["maps.googleapis.com"])
        assertEquals(1, usage.kinds["directions"])
        assertEquals(1, usage.blocked["play.google.com"])
        GoogleRequestCounter.clear()
    }

    @Test fun `restore merges and drops days past the retention window`() {
        GoogleRequestCounter.clear()
        val today = GoogleRequestCounter.today()
        GoogleRequestCounter.recordSentHost("www.google.com", "search", today)
        val old = "2000-01-01"
        GoogleRequestCounter.restore(
            """{"version":1,"days":{"$today":{"sent":{"www.google.com":4}},"$old":{"sent":{"www.google.com":9}}}}""",
        )
        assertEquals(5, GoogleRequestCounter.snapshot()[today]!!.sent["www.google.com"])
        assertFalse(GoogleRequestCounter.snapshot().containsKey(old))
        GoogleRequestCounter.clear()
    }

    @Test fun `clear empties the count and leaves nothing to restore`() {
        GoogleRequestCounter.clear()
        GoogleRequestCounter.recordSentHost("www.google.com", "search", day)
        GoogleRequestCounter.clear()
        assertTrue(GoogleRequestCounter.snapshot().isEmpty())
        assertTrue(GoogleRequestCounter.rows().isEmpty())
        assertTrue(GoogleRequestCounter.hostRows().isEmpty())
        assertTrue(GoogleRequestCounter.save().contains("\"days\":{}"))
        GoogleRequestCounter.recordSentHost("www.google.com", "search", day)
        assertEquals(1, GoogleRequestCounter.totalTodayForTest(day))
        GoogleRequestCounter.clear()
    }

    @Test fun `rows report today and the week per purpose and per host`() {
        GoogleRequestCounter.clear()
        val today = GoogleRequestCounter.today()
        GoogleRequestCounter.recordSentHost("www.google.com", "search", today)
        GoogleRequestCounter.recordSentHost("www.google.com", "photos", today)
        GoogleRequestCounter.recordSentHost("lh3.googleusercontent.com", "images", today)
        GoogleRequestCounter.recordSentHost("www.google.com", "search", "2000-01-01")
        val kinds = GoogleRequestCounter.rows().associate { it.label to (it.today to it.week) }
        assertEquals(1 to 1, kinds["search"])
        assertEquals(1 to 1, kinds["photos"])
        assertEquals(1 to 1, kinds["images"])
        val hosts = GoogleRequestCounter.hostRows().associate { it.label to (it.today to it.week) }
        assertEquals(2 to 2, hosts["www.google.com"])
        assertEquals(1 to 1, hosts["lh3.googleusercontent.com"])
        assertEquals("greq=3 gblocked=0", GoogleRequestCounter.debugLine())
        GoogleRequestCounter.clear()
    }
}

/** The day-keyed total, for a test that must not depend on the machine's date. */
private fun GoogleRequestCounter.totalTodayForTest(day: String): Int = snapshot()[day]?.sent?.values?.sum() ?: 0
