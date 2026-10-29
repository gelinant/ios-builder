package app.vela.ios.world

import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.ios.search.FakeHttp
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Cloudflare Radar: token presence, outages, attacks, the 30 minute window and the missing token. */
class RadarStoreTest {
    private val now = 1_793_185_200_000L
    private val token = "cf-secret-token-42"

    private val outagesJson = """
        {"success":true,"result":{"annotations":[
          {"id":"550","scope":"Colima, Mexico","startDate":"2026-10-28T10:10:00Z","endDate":null,
           "locations":["MX"],"linkedUrl":"https://example.invalid/outage",
           "outage":{"outageCause":"CABLE_CUT","outageType":"NATIONWIDE"}},
          {"id":"551","scope":"Ukraine","startDate":"2026-10-28T09:00:00Z","endDate":null,
           "locations":["UA"],"outage":{"outageCause":"POWER_OUTAGE","outageType":"REGIONAL"}}
        ]}}
    """.trimIndent()

    private val attacksJson = """
        {"success":true,"result":{
          "meta":{"dateRange":{"startTime":"2026-10-21T00:00:00Z","endTime":"2026-10-28T00:00:00Z"}},
          "top_0":[
            {"originCountryAlpha2":"FR","originCountryName":"France","targetCountryAlpha2":"US",
             "targetCountryName":"United States","value":"4.323214"},
            {"originCountryAlpha2":"RU","originCountryName":"Russia","value":"3.1"}
          ]}}
    """.trimIndent()

    @Test fun missingTokenMakesNoRequestAndSaysKeyRequired() = runTest {
        val requests = mutableListOf<HttpRequest>()
        val store = RadarStore(FakeHttp { req -> requests += req; error("no request without a token") })
        assertNull(store.refresh(null, now))
        assertTrue(requests.isEmpty(), "a missing token must not send an empty Authorization header")
        val state = store.state(now)
        assertEquals("key_required", state.status)
        assertEquals(0, state.eventCount)
        assertFalse(state.tokenPresent)
        assertEquals("radar_state=key_required radar_events=0", state.debugLine)
        assertNull(store.refresh("   ", now))
        assertEquals("key_required", store.state(now).status)
    }

    @Test fun outagesAndAttacksBecomeDatedEvents() = runTest {
        val requests = mutableListOf<HttpRequest>()
        val http = FakeHttp { req ->
            requests += req
            when {
                req.url.contains("/annotations/outages") -> ok(outagesJson, req)
                req.url.contains("/top/attacks") -> ok(attacksJson, req)
                else -> error("unexpected ${req.url}")
            }
        }
        val store = RadarStore(http)
        val snapshot = assertNotNull(store.refresh(token, now))
        assertEquals(4, snapshot.events.size)
        assertEquals(2, snapshot.events.count { it.kind == "outage" })
        assertEquals(2, snapshot.events.count { it.kind == "attack" })
        val cable = snapshot.events.single { it.id == "outage-550" }
        assertEquals("Colima, Mexico", cable.title)
        assertEquals(listOf("MX"), cable.locations)
        assertEquals("cable cut, nationwide", cable.detail)
        assertEquals(1_793_182_200_000L, cable.startedAtMs)
        val attack = snapshot.events.first { it.id == "attack-0-FR-US" }
        assertEquals("Attack from France to United States", attack.title)
        assertEquals(listOf("FR", "US"), attack.locations)
        assertEquals(2, requests.size)
        assertEquals("Bearer $token", requests.first().headers.single {
            it.name == "Authorization"
        }.value)
        val state = store.state(now + 60_000L)
        assertEquals(WorldLayerStatuses.FRESH, state.status)
        assertEquals(4, state.eventCount)
        assertEquals(60L, state.ageSeconds)
    }

    @Test fun dataExpiresAfterThirtyMinutesAndAQuietFeedIsStillFresh() = runTest {
        val http = FakeHttp { req ->
            if (req.url.contains("/annotations/outages")) {
                ok("""{"success":true,"result":{"annotations":[]}}""", req)
            } else {
                ok("""{"success":true,"result":{"meta":{},"top_0":[]}}""", req)
            }
        }
        val store = RadarStore(http)
        val snapshot = assertNotNull(store.refresh(token, now))
        assertTrue(snapshot.events.isEmpty())
        val quiet = store.state(now + 1_000L)
        assertEquals(WorldLayerStatuses.FRESH, quiet.status, "a quiet Cloudflare feed is not unavailable")
        assertEquals(0, quiet.eventCount)

        assertEquals(WorldLayerStatuses.FRESH, store.state(now + 1_800_000L).status)
        assertEquals(WorldLayerStatuses.LATE, store.state(now + 1_801_000L).status)
    }

    @Test fun removingTheTokenClearsEventsAndNeverLeaksTheToken() = runTest {
        val http = FakeHttp { req ->
            if (req.url.contains("/annotations/outages")) ok(outagesJson, req)
            else ok(attacksJson, req)
        }
        val store = RadarStore(http)
        val snapshot = assertNotNull(store.refresh(token, now))
        assertFalse(snapshot.toString().contains(token), "the snapshot carried the token")
        assertFalse(store.state(now).toString().contains(token), "the state carried the token")
        assertFalse(store.state(now).debugLine.contains(token), "the debug line carried the token")

        assertNull(store.refresh(null, now + 1_000L))
        val state = store.state(now + 1_000L)
        assertEquals("key_required", state.status)
        assertEquals(0, state.eventCount, "a removed token must not leave stale events on screen")
        assertFalse(state.toString().contains(token))
    }

    @Test fun keychainPresenceLeavesNoPlaintextInTheSettingsStore() {
        val stores = RadarMemStores()
        val secrets = RadarMemSecrets()
        val settings = WorldLayerSettings(stores, secrets)
        settings.setKey("energy", token)
        assertTrue(settings.keyPresent("energy"))
        assertEquals(token, secrets.saved("world_layer_energy_key"))
        val state = settings.state("energy", installed = true, nowMs = now)
        assertTrue(state.keyPresent)
        assertFalse(state.toString().contains(token), "the layer state carried the token")
        val flags = stores.open(WorldLayerSettings.STORE)
        for (key in flags.keys()) {
            assertFalse(flags.getString(key, null)?.contains(token) == true, "$key leaked the token")
        }
        assertFalse(flags.contains("world_layer_energy_key"))
    }
}

private fun ok(body: String, req: HttpRequest) =
    HttpResponse(200, emptyList(), body.encodeToByteArray(), req.url)

private class RadarMemSecrets : WorldSecretStore {
    private val values = mutableMapOf<String, String>()
    override fun has(secretId: String): Boolean = values.containsKey(secretId)
    override fun put(secretId: String, value: String): Boolean {
        values[secretId] = value
        return true
    }
    override fun remove(secretId: String) {
        values.remove(secretId)
    }
    fun saved(secretId: String): String? = values[secretId]
}

private class RadarMemStores : KeyValueStores {
    private val stores = mutableMapOf<String, RadarMemStore>()
    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { RadarMemStore() }
}

private class RadarMemStore : KeyValueStore {
    private val values = mutableMapOf<String, Any>()
    override fun contains(key: String) = values.containsKey(key)
    override fun getString(key: String, default: String?): String? = values[key] as? String ?: default
    override fun getLong(key: String, default: Long): Long = values[key] as? Long ?: default
    override fun getInt(key: String, default: Int): Int = values[key] as? Int ?: default
    override fun getBoolean(key: String, default: Boolean): Boolean = values[key] as? Boolean ?: default
    override fun getFloat(key: String, default: Float): Float = values[key] as? Float ?: default
    override fun keys(): Set<String> = values.keys.toSet()
    override fun edit(): KeyValueEditor = object : KeyValueEditor {
        private val changes = mutableMapOf<String, Any?>()
        private var clear = false
        override fun putString(key: String, value: String?): KeyValueEditor = change(key, value)
        override fun putLong(key: String, value: Long): KeyValueEditor = change(key, value)
        override fun putInt(key: String, value: Int): KeyValueEditor = change(key, value)
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = change(key, value)
        override fun putFloat(key: String, value: Float): KeyValueEditor = change(key, value)
        override fun remove(key: String): KeyValueEditor = change(key, null)
        override fun clear(): KeyValueEditor { clear = true; return this }
        private fun change(key: String, value: Any?): KeyValueEditor {
            changes[key] = value
            return this
        }
        override fun apply() {
            if (clear) values.clear()
            for ((key, value) in changes) {
                if (value == null) values.remove(key) else values[key] = value
            }
        }
        override fun commit(): Boolean { apply(); return true }
    }
}
