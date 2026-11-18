package app.vela.ios

import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals

class IosGraphTest {
    @Test fun shortRoadNameGoesThroughCoreCommon() {
        assertEquals("W Covell Blvd", IosGraph.shortRoadName("West Covell Boulevard"))
    }

    @Test fun selfCheckNamesTheVersionAndTheShortName() = runTest {
        assertEquals("VelaCore ${IosGraph.frameworkVersion}: West Covell Boulevard -> W Covell Blvd", IosGraph.selfCheck())
    }
}
