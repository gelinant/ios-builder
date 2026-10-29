package app.vela.core.offline

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** Manifest rows carry the optional pack counts and the delta object; both survive parsing. */
class RegionCatalogTest {
    @Test fun aPackRowKeepsItsCountsAndDelta() {
        val rows = RegionCatalog.parseManifest(
            """
            {"regions":[{
              "id":"monaco","name":"Monaco","url":"https://example.invalid/monaco.zip",
              "sizeMb":2,"installedMb":5,"bbox":[43.72,7.40,43.76,7.44],"rev":7,
              "counts":{"poi":120,"addr":30,"streetname":4,"streetpt":900},
              "delta":{"url":"https://example.invalid/monaco.vpatch","fromRev":6,"sizeMb":1}
            }]}
            """,
        )
        val row = rows.single()
        assertEquals(7, row.rev)
        assertEquals(2, row.sizeMb)
        assertEquals(5, row.installedMb)
        assertEquals(mapOf("poi" to 120L, "addr" to 30L, "streetname" to 4L, "streetpt" to 900L), row.counts)
        assertEquals("https://example.invalid/monaco.vpatch", row.deltaUrl)
        assertEquals(6, row.deltaFromRev)
        assertEquals(1, row.deltaSizeMb)
    }

    @Test fun aRowWithoutADeltaKeepsTheEmptyDefaults() {
        val row = RegionCatalog.parseManifest(
            """
            {"regions":[{
              "id":"monaco","name":"Monaco","url":"https://example.invalid/monaco.pmtiles",
              "sizeMb":1,"bbox":[43.72,7.40,43.76,7.44],"rev":3
            }]}
            """,
        ).single()
        assertEquals(emptyMap(), row.counts)
        assertNull(row.deltaUrl)
        assertEquals(0, row.deltaFromRev)
        assertEquals(0, row.deltaSizeMb)
    }

    @Test fun anUnreadableCountDoesNotDropTheRow() {
        val row = RegionCatalog.parseManifest(
            """
            {"regions":[{
              "id":"monaco","name":"Monaco","url":"https://example.invalid/monaco.zip",
              "sizeMb":1,"bbox":[43.72,7.40,43.76,7.44],"counts":{"poi":"12","addr":null}
            }]}
            """,
        ).single()
        assertEquals(mapOf("poi" to 12L), row.counts)
    }
}
