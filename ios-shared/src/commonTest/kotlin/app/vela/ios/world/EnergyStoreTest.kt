package app.vela.ios.world

import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.ios.search.FakeHttp
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The keyless NESO feed, its 14 British regions, the 30 minute window and the no-key answer. */
class EnergyStoreTest {
    private val fromIso = "2026-10-28T11:00Z"
    private val fromMs = 1_793_185_200_000L // 2026-10-28T11:00Z

    private val zonesJson = """
        {"regions":[
          {"regionId":1,"name":"North Scotland","center":[57.2,-4.4],"radiusKm":95},
          {"regionId":2,"name":"South Scotland","center":[55.6,-3.7],"radiusKm":90},
          {"regionId":3,"name":"North West England","center":[54.3,-2.7],"radiusKm":70},
          {"regionId":4,"name":"North East England","center":[54.8,-1.6],"radiusKm":70},
          {"regionId":5,"name":"Yorkshire","center":[53.8,-1.0],"radiusKm":75},
          {"regionId":6,"name":"North Wales & Merseyside","center":[53.1,-3.5],"radiusKm":55},
          {"regionId":7,"name":"South Wales","center":[52.0,-3.8],"radiusKm":60},
          {"regionId":8,"name":"West Midlands","center":[52.4,-2.3],"radiusKm":60},
          {"regionId":9,"name":"East Midlands","center":[52.9,-0.9],"radiusKm":65},
          {"regionId":10,"name":"East England","center":[52.3,0.5],"radiusKm":80},
          {"regionId":11,"name":"South West England","center":[50.9,-3.8],"radiusKm":90},
          {"regionId":12,"name":"South England","center":[51.3,-1.5],"radiusKm":80},
          {"regionId":13,"name":"London","center":[51.6,-0.0],"radiusKm":25},
          {"regionId":14,"name":"South East England","center":[51.2,0.3],"radiusKm":65}
        ]}
    """.trimIndent()

    private val nesoJson = """
        {"data":[{"from":"$fromIso","to":"2026-10-28T11:30Z","regions":[
          {"regionid":1,"shortname":"North Scotland","dnoregion":"Scottish Hydro Electric Power Distribution","intensity":{"forecast":0,"index":"very low"}},
          {"regionid":2,"shortname":"South Scotland","dnoregion":"SP Distribution","intensity":{"forecast":25,"index":"very low"}},
          {"regionid":3,"shortname":"North West England","dnoregion":"Electricity North West","intensity":{"forecast":60,"index":"low"}},
          {"regionid":4,"shortname":"North East England","dnoregion":"NPG North East","intensity":{"forecast":90,"index":"low"}},
          {"regionid":5,"shortname":"Yorkshire","dnoregion":"NPG Yorkshire","intensity":{"forecast":120,"index":"moderate"}},
          {"regionid":6,"shortname":"North Wales & Merseyside","dnoregion":"SP Manweb","intensity":{"forecast":150,"index":"moderate"}},
          {"regionid":7,"shortname":"South Wales","dnoregion":"WPD South Wales","intensity":{"forecast":205,"index":"high"}},
          {"regionid":8,"shortname":"West Midlands","dnoregion":"WPD West Midlands","intensity":{"forecast":23,"index":"very low"}},
          {"regionid":9,"shortname":"East Midlands","dnoregion":"WPD East Midlands","intensity":{"forecast":85,"index":"low"}},
          {"regionid":10,"shortname":"East England","dnoregion":"UKPN East","intensity":{"forecast":61,"index":"low"}},
          {"regionid":11,"shortname":"South West England","dnoregion":"WPD South West","intensity":{"forecast":32,"index":"very low"}},
          {"regionid":12,"shortname":"South England","dnoregion":"SSE Southern England","intensity":{"forecast":95,"index":"low"}},
          {"regionid":13,"shortname":"London","dnoregion":"UKPN London","intensity":{"forecast":170,"index":"high"}},
          {"regionid":14,"shortname":"South East England","dnoregion":"UKPN South East","intensity":{"forecast":250,"index":"very high"}},
          {"regionid":15,"shortname":"England","dnoregion":"England","intensity":{"forecast":49,"index":"low"}},
          {"regionid":16,"shortname":"Scotland","dnoregion":"Scotland","intensity":{"forecast":10,"index":"very low"}}
        ]}]}
    """.trimIndent()

    @Test fun keepsTheFourteenBritishRegionsAndDropsAggregates() {
        val zones = NesoZones.parse(zonesJson)
        assertEquals(14, zones.size)
        assertEquals((1..14).toList(), zones.map { it.regionId })

        val snapshot = assertNotNull(CarbonIntensitySource.parse(nesoJson, zones))
        assertEquals(fromMs, snapshot.fromMs)
        assertEquals(14, snapshot.regions.size)
        assertEquals((1..14).toList(), snapshot.regions.map { it.regionId })
        val london = snapshot.regions.single { it.regionId == 13 }
        assertEquals("London", london.name)
        assertEquals(170, london.forecastGrams)
        assertEquals("high", london.index)
        assertEquals(51.6, london.latitude)
        assertFalse(snapshot.regions.any { it.regionId >= 15 }, "an aggregate is not a zone")
    }

    @Test fun malformedOrAggregateOnlyAnswersAreRejected() {
        val zones = NesoZones.parse(zonesJson)
        assertNull(CarbonIntensitySource.parse("{}", zones))
        assertNull(CarbonIntensitySource.parse("not json", zones))
        val aggregateOnly = """
            {"data":[{"from":"$fromIso","to":"2026-10-28T11:30Z","regions":[
              {"regionid":15,"shortname":"England","dnoregion":"England","intensity":{"forecast":49,"index":"low"}}
            ]}]}
        """.trimIndent()
        assertNull(CarbonIntensitySource.parse(aggregateOnly, zones),
            "an aggregate alone must not become a drawn region")
    }

    @Test fun forecastExpiresAfterThirtyMinutes() {
        val zones = NesoZones.parse(zonesJson)
        val snapshot = assertNotNull(CarbonIntensitySource.parse(nesoJson, zones))
        val store = EnergyStore(
            CarbonIntensitySource(FakeHttp { error("no request") }),
            ElectricityMapsSource(FakeHttp { error("no request") }),
        )
        val fresh = store.stateOf(snapshotFor(snapshot), fromMs + 60_000L)
        assertEquals(WorldLayerStatuses.FRESH, fresh.status)
        assertEquals(60L, fresh.ageSeconds)

        val atEdge = store.stateOf(snapshotFor(snapshot), fromMs + 1_800_000L)
        assertEquals(WorldLayerStatuses.FRESH, atEdge.status, "30 minutes is still inside the window")

        val late = store.stateOf(snapshotFor(snapshot), fromMs + 1_801_000L)
        assertEquals(WorldLayerStatuses.LATE, late.status)
        assertEquals(WorldLayerStatuses.UNAVAILABLE, store.stateOf(null, fromMs).status)
    }

    @Test fun missingElectricityMapsKeyIsKeyRequiredAndMakesNoMapsRequest() = runTest {
        val requests = mutableListOf<HttpRequest>()
        val http = FakeHttp { req ->
            requests += req
            if (req.url.contains("carbonintensity")) {
                ok(nesoJson, req)
            } else {
                error("Electricity Maps must not be called without a key")
            }
        }
        val store = EnergyStore(
            CarbonIntensitySource(http),
            ElectricityMapsSource(http),
        )
        val snapshot = assertNotNull(store.refresh(NesoZones.parse(zonesJson), null, fromMs))
        assertFalse(snapshot.electricityMapsKeyPresent)
        assertEquals("key_required", snapshot.electricityMapsState)
        assertTrue(snapshot.electricityMaps.isEmpty())
        assertEquals(1, requests.size, "only the keyless NESO request may run")
        assertEquals(WorldLayerStatuses.FRESH, store.state(fromMs + 1_000L).status)
    }

    @Test fun storedElectricityMapsKeyIsSentAndNeverCopiedIntoTheSnapshot() = runTest {
        val key = "em-secret-key-42"
        val requests = mutableListOf<HttpRequest>()
        val http = FakeHttp { req ->
            requests += req
            if (req.url.contains("carbonintensity")) ok(nesoJson, req)
            else ok("""{"zone":"GB","carbonIntensity":88,"updatedAt":"2026-10-28T11:05:00Z"}""", req)
        }
        val store = EnergyStore(CarbonIntensitySource(http), ElectricityMapsSource(http))
        val snapshot = assertNotNull(
            store.refresh(NesoZones.parse(zonesJson), key, fromMs + 300_000L))
        assertTrue(snapshot.electricityMapsKeyPresent)
        assertEquals("ok", snapshot.electricityMapsState)
        assertEquals(88, snapshot.electricityMaps.single().carbonIntensity)
        assertEquals(key, requests.last().headers.single { it.name == "auth-token" }.value)
        assertFalse(snapshot.toString().contains(key), "the snapshot carried the key")
        assertFalse(store.state(fromMs).toString().contains(key), "the state carried the key")
    }

    @Test fun unknownIndexFallsBackToTheForecastBands() {
        assertEquals("very low", CarbonIntensitySource.indexFor(0))
        assertEquals("low", CarbonIntensitySource.indexFor(100))
        assertEquals("moderate", CarbonIntensitySource.indexFor(150))
        assertEquals("high", CarbonIntensitySource.indexFor(200))
        assertEquals("very high", CarbonIntensitySource.indexFor(201))
    }

    private fun snapshotFor(carbon: CarbonSnapshot) = EnergySnapshot(
        carbon = carbon,
        electricityMaps = emptyList(),
        electricityMapsKeyPresent = false,
        fetchedAtMs = carbon.fromMs,
    )

    private fun ok(body: String, req: HttpRequest) =
        HttpResponse(200, emptyList(), body.encodeToByteArray(), req.url)
}
