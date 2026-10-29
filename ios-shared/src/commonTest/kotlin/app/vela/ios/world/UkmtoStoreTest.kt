package app.vela.ios.world

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The UKMTO list carries a title, a date and a link, newest first, and nothing else. */
class UkmtoStoreTest {
    private val now = 1_790_000_000_000L

    private val fixture = """
        [
          {
            "incidentIssuer": "UKMTO",
            "incidentNumber": 143,
            "sitecoreId": "a5b33f9d-6c8e-43fc-9af0-3936d61bf55d",
            "utcDateCreated": "2026-09-29T10:28:14Z",
            "utcDateOfIncident": "2026-09-28T23:00:00Z",
            "incidentTypeName": "Suspicious Activity",
            "locationLatitude": 26.433333,
            "locationLongitude": 56.486111,
            "place": "Strait of Hormuz",
            "otherDetails": "SECRET BODY THAT MUST NOT BE COPIED"
          },
          {
            "incidentIssuer": "UKMTO",
            "incidentNumber": 154,
            "sitecoreId": "0077459b-d614-43e7-aa9e-0b8828ea2ad9",
            "utcDateCreated": "2026-10-12T12:00:00Z",
            "utcDateOfIncident": "2026-10-12T10:00:00Z",
            "incidentTypeName": "Attack",
            "locationLatitude": 26.1,
            "locationLongitude": 56.2,
            "otherDetails": "ANOTHER BODY"
          },
          {
            "incidentNumber": 155,
            "utcDateOfIncident": "2026-10-13T10:00:00Z",
            "incidentTypeName": "Attack"
          },
          {
            "incidentNumber": 156,
            "sitecoreId": "no-date",
            "incidentTypeName": "Advisory"
          }
        ]
    """.trimIndent()

    @Test fun parseKeepsTitleDateAndLinkOnly() {
        val incidents = UkmtoStore.parse(fixture)
        assertEquals(2, incidents.size, "an entry without a link or a date is dropped")
        val newest = incidents.first()
        assertEquals("UKMTO #154 Attack", newest.title)
        assertEquals("12 Oct 2026", newest.dateLabel)
        assertEquals(
            "https://www.ukmto.org/recent-incidents#0077459b-d614-43e7-aa9e-0b8828ea2ad9",
            newest.link)
        assertTrue(newest.dateMs > incidents[1].dateMs, "newest first")
        assertEquals("UKMTO #143 Suspicious Activity", incidents[1].title)
    }

    @Test fun noSummaryTextAndNoCoordinateReachesARow() {
        val incidents = UkmtoStore.parse(fixture)
        val text = incidents.joinToString(" ") { "${it.title} ${it.dateLabel} ${it.link}" }
        assertFalse(text.contains("SECRET BODY"))
        assertFalse(text.contains("Strait of Hormuz"))
        assertFalse(text.contains("26.433"), "no coordinate is kept")
    }

    @Test fun refreshBuildsALinkOnlyListWithAHeaderFirst() = runTest {
        val store = UkmtoStore(fetchText = { fixture }, now = { now })
        val snapshot = assertNotNull(store.refresh())
        assertEquals(3, snapshot.rows.size, "header plus two incidents")
        val header = snapshot.rows.first()
        assertEquals("maritime-ukmto-header", header.id)
        assertEquals("UKMTO incidents: link list only", header.title)
        assertTrue(header.detail.contains("Not a live advisory feed"))
        assertNull(header.lat)
        for (row in snapshot.rows.drop(1)) {
            assertTrue(row.detail.startsWith("12 Oct 2026")
                || row.detail.startsWith("28 Sep 2026"))
            assertTrue(row.detail.contains("Link only"))
            assertTrue(row.detail.contains("https://www.ukmto.org/recent-incidents#"))
            assertNull(row.lat, "the UKMTO list never carries a point")
            assertNull(row.lng)
        }
    }

    @Test fun emptyAnswerSaysSoRatherThanShowingNothing() = runTest {
        val store = UkmtoStore(fetchText = { "[]" }, now = { now })
        val snapshot = assertNotNull(store.refresh())
        assertEquals(2, snapshot.rows.size)
        assertEquals("maritime-ukmto-empty", snapshot.rows[1].id)
        assertTrue(snapshot.rows[1].title.contains("no incident"))
    }

    @Test fun tenMinuteCacheAndFailureKeepsTheOldList() = runTest {
        var clock = now
        var calls = 0
        var answer: String? = fixture
        val store = UkmtoStore(fetchText = { calls++; answer }, now = { clock })
        assertNotNull(store.refresh())
        assertEquals(1, calls)
        assertNotNull(store.refresh())
        assertEquals(1, calls, "a second call inside ten minutes uses the cache")

        clock = now + 10 * 60_000L + 1_000L
        answer = null
        val kept = assertNotNull(store.refresh())
        assertEquals(2, calls)
        assertEquals(2, kept.incidents.size, "a failed refresh keeps the previous list")

        val cold = UkmtoStore(fetchText = { null }, now = { clock })
        assertNull(cold.refresh(), "no list and no answer is unavailable, not empty")
    }
}
