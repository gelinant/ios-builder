package app.vela.ios.offline

import app.vela.core.offline.RoutingRegion
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertTrue

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

    @Test fun regionPlanRoundTripKeepsEveryPieceAndFailure() {
        val plan = PendingRegionDownload(
            record = InstalledRegion(
                id = "monaco", packId = "monaco",
                places = listOf(InstalledArchive("monaco", 43.7, 7.4, 43.8, 7.5)),
                maps = listOf(InstalledArchive("monaco", 43.7, 7.4, 43.8, 7.5)),
            ),
            assets = listOf(
                OfflineAssetPlan("monaco", "pack", "https://example.invalid/pack", "/data/pack.db"),
                OfflineAssetPlan("map-fonts", "glyphs", "https://example.invalid/fonts", "/data/glyphs"),
            ),
            failed = true,
        )
        val decoded = Json.decodeFromString<PendingRegionDownload>(
            Json.encodeToString(PendingRegionDownload.serializer(), plan))
        assertEquals(plan, decoded)
        assertEquals(2, decoded.assets.size)
        assertTrue(decoded.failed)
    }

    @Test fun roadNamesReadLocalArchiveBeforeNetwork() = runTest {
        var onlineCalls = 0
        val local = byteArrayOf(1, 2, 3)
        val answer = OfflineStore.roadTile(
            paths = listOf("/data/first.pmtiles", "/data/second.pmtiles"), z = 14, x = 1, y = 2,
            read = { path, _, _, _ -> if (path.endsWith("second.pmtiles")) local else null },
            online = { onlineCalls++; byteArrayOf(9) },
        )
        assertContentEquals(local, answer)
        assertEquals(0, onlineCalls)
    }

    @Test fun roadNamesFallBackToOpenFreeMapWithoutALocalTile() = runTest {
        val online = byteArrayOf(9)
        val answer = OfflineStore.roadTile(
            paths = listOf("/data/first.pmtiles"), z = 14, x = 1, y = 2,
            read = { _, _, _, _ -> null },
            online = { online },
        )
        assertContentEquals(online, answer)
        assertContentEquals(online, OfflineStore.roadTile(emptyList(), 14, 1, 2, online = { online }))
    }
}
