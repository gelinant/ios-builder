package app.vela.ios.offline

import app.vela.core.offline.RoutingRegion
import kotlin.test.Test
import kotlin.test.assertEquals

private fun region(id: String, s: Double, w: Double, n: Double, e: Double) = RoutingRegion(
    id = id, name = id, url = "https://example.invalid/$id", sizeMb = 1,
    s = s, w = w, n = n, e = e,
)

class OfflineStoreTest {
    @Test fun ownArchiveWinsOverEveryContainedTestArchive() {
        val region = region("california-norcal", 35.0, -126.0, 42.0, -115.0)
        val archives = listOf(
            region("davis", 38.52, -121.8, 38.58, -121.7),
            region("california-norcal", 35.0, -126.0, 42.0, -115.0),
        )
        assertEquals(listOf("california-norcal"), OfflineStore.archivesFor(region, archives).map { it.id })
    }

    @Test fun aCountryPullsEveryArchivePieceWhoseCenterItCovers() {
        val country = region("country", 40.0, 0.0, 50.0, 10.0)
        val archives = listOf(
            region("north", 45.0, 0.0, 50.0, 10.0),
            region("south", 40.0, 0.0, 45.0, 10.0),
            region("elsewhere", 20.0, 0.0, 30.0, 10.0),
        )
        assertEquals(listOf("north", "south"), OfflineStore.archivesFor(country, archives).map { it.id })
    }

    @Test fun aSmallRegionWithoutItsOwnArchiveUsesTheSmallestCoveringOne() {
        val small = region("small", 42.4, 1.4, 42.7, 1.8)
        val archives = listOf(
            region("large", 30.0, -10.0, 60.0, 20.0),
            region("closer", 40.0, 0.0, 45.0, 5.0),
        )
        assertEquals(listOf("closer"), OfflineStore.archivesFor(small, archives).map { it.id })
    }
}
