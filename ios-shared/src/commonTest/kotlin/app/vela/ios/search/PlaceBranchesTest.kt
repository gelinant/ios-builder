package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PlaceBranchesTest {
    private fun place(
        id: String,
        name: String = id,
        address: String?,
        lat: Double = 38.5449,
        lng: Double = -121.7405,
        featureId: String? = "f:$id",
    ) = Place(
        id = id,
        name = name,
        location = LatLng(lat, lng),
        address = address,
        category = "Cafe",
        featureId = featureId,
    )

    @Test fun streetKeyDropsTheSuiteAndTheTown() {
        assertEquals("123 g st", PlaceBranches.streetKey("123 G St, Davis, CA 95616"))
        assertEquals("123 g st", PlaceBranches.streetKey("123 G St, Suite 2, Davis, CA"))
        assertEquals("123 g st", PlaceBranches.streetKey("123 G St Ste 4"))
        assertEquals("45 main street", PlaceBranches.streetKey("45 Main Street, Unit B"))
        assertNull(PlaceBranches.streetKey(null))
        assertNull(PlaceBranches.streetKey(" , Davis"))
    }

    @Test fun sameStreetLineWithinSixtyMetersIsABranch() {
        val selected = place("a", address = "123 G St, Davis, CA")
        val bakery = place("b", address = "123 G St, Suite 2, Davis, CA", lat = 38.54491)
        val across = place("c", address = "125 G St, Davis, CA", lat = 38.54492)
        val far = place("d", address = "123 G St, Davis, CA", lat = 38.5456)

        val got = PlaceBranches.companions(selected, listOf(selected, bakery, across, far))
        assertEquals(listOf("b"), got.map { it.id })
    }

    @Test fun withoutAnAddressOnlyTheFootprintCounts() {
        val selected = place("a", address = null)
        val neighbor = place("b", address = null, lat = 38.54495, lng = -121.7405)
        val downTheRoad = place("c", address = null, lat = 38.5451)

        val got = PlaceBranches.companions(selected, listOf(selected, neighbor, downTheRoad))
        assertEquals(listOf("b"), got.map { it.id })
    }

    @Test fun oneSideWithoutAddressStillNeedsTheSameFootprint() {
        val selected = place("a", address = "123 G St, Davis, CA")
        val bareAtTheDoor = place("b", address = null, lat = 38.54492)
        val bareAcrossTown = place("c", address = null, lat = 38.5465)

        val got = PlaceBranches.companions(selected, listOf(bareAtTheDoor, bareAcrossTown))
        assertEquals(listOf("b"), got.map { it.id })
    }

    @Test fun theSelectedListingIsDroppedByIdThenByName() {
        val selected = place("a", name = "Market Hall", address = "123 G St", featureId = "f:shared")
        val sameFeature = place("b", name = "Market Hall Cafe", address = "123 G St", featureId = "f:shared")
        val noFeature = place("c", name = "Market Hall", address = "123 G St", featureId = null)
        val selectedNoFeature = selected.copy(featureId = null)

        assertEquals(
            emptyList(),
            PlaceBranches.companions(selected, listOf(selected, sameFeature)).map { it.id },
        )
        assertTrue(PlaceBranches.companions(selectedNoFeature, listOf(noFeature)).isEmpty())
    }

    @Test fun theListKeepsTheReplyOrderAndStopsAtSix() {
        val selected = place("a", address = "123 G St")
        val candidates = (1..8).map { place("b$it", address = "123 G St", lat = 38.5449 + it * 0.00001) }

        val got = PlaceBranches.companions(selected, candidates)
        assertEquals(6, got.size)
        assertEquals(listOf("b1", "b2", "b3", "b4", "b5", "b6"), got.map { it.id })
    }

    @Test fun noCandidateMeansNoBranchAndNothingIsDrawn() {
        val selected = place("a", address = "123 G St")
        assertTrue(PlaceBranches.companions(selected, emptyList()).isEmpty())
        assertTrue(PlaceBranches.companions(selected, listOf(place("b", address = "500 K St"))).isEmpty())
    }

    @Test fun theFixtureIsOneShopAndThreeNeighborsAtOneAddress() {
        val all = PlaceBranches.fixture()
        assertEquals(4, all.size)
        val selected = all.first()
        val branches = PlaceBranches.companions(selected, all)
        assertEquals(3, branches.size)
        assertTrue(branches.all { PlaceBranches.streetKey(it.address) == "123 g st" })
    }
}
