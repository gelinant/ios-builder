package app.vela.ios.world

import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The world-layer switches, key presence and the three freshness states, without a network. */
class WorldLayerSettingsTest {
    private val now = 1_700_000_000_000L

    @Test fun switchesPersistUnderStableKeysAndStartOff() {
        val stores = MemStores()
        val first = WorldLayerSettings(stores, MemSecrets())
        for (spec in WorldLayerCatalog.ALL) {
            assertFalse(first.isEnabled(spec.id), "${spec.id} must start off")
        }
        first.setEnabled("aviation", true)
        first.setEnabled("wiki", true)
        assertTrue(first.isEnabled("aviation"))
        assertTrue(first.isEnabled("wiki"))
        assertFalse(first.isEnabled("maritime"))

        val flags = stores.open(WorldLayerSettings.STORE)
        assertTrue(flags.getBoolean("world_layer_aviation_on", false))
        assertEquals("world_layer_wiki_on", WorldLayerSettings.flagKey("wiki"))

        val second = WorldLayerSettings(stores, MemSecrets())
        assertTrue(second.isEnabled("aviation"), "the switch survives a new process")
        second.setEnabled("aviation", false)
        assertFalse(second.isEnabled("aviation"))
        assertFalse(stores.open(WorldLayerSettings.STORE)
            .getBoolean("world_layer_aviation_on", true))
    }

    @Test fun keyPresenceNeverWritesPlaintext() {
        val stores = MemStores()
        val secrets = MemSecrets()
        val settings = WorldLayerSettings(stores, secrets)

        assertFalse(settings.keyPresent("notam"))
        settings.setKey("notam", "  notam-test-key-42  ")
        assertTrue(settings.keyPresent("notam"), "the presence flag follows the secret store")
        assertEquals("notam-test-key-42", secrets.saved("world_layer_notam_key"))

        val state = settings.state("notam", installed = true, nowMs = now)
        assertTrue(state.needsKey)
        assertTrue(state.keyPresent)
        assertTrue(state.available)
        assertFalse(state.toString().contains("notam-test-key-42"), "the state carries no plaintext")

        val flags = stores.open(WorldLayerSettings.STORE)
        for (key in flags.keys()) {
            val value = flags.getString(key, null)
            assertFalse(value?.contains("notam-test-key-42") == true, "$key leaked the key")
        }
        assertFalse(flags.contains("world_layer_notam_key"))

        settings.clearKey("notam")
        assertFalse(settings.keyPresent("notam"))
        assertEquals(null, secrets.saved("world_layer_notam_key"))
    }

    @Test fun requiredKeyWithoutOneIsUnavailable() {
        val settings = WorldLayerSettings(MemStores(), MemSecrets())
        val missing = settings.state("notam", installed = true, nowMs = now)
        assertEquals(WorldLayerStatuses.UNAVAILABLE, missing.status)
        assertFalse(missing.available)

        val keyless = settings.state("wiki", installed = true, nowMs = now)
        assertEquals(WorldLayerStatuses.UNAVAILABLE, keyless.status, "no data is not fresh")
        assertTrue(keyless.available)
    }

    @Test fun freshnessFollowsEachLayersOwnMaxAge() {
        val settings = WorldLayerSettings(MemStores(), MemSecrets())

        settings.markUpdated("aviation", now - 60_000L)
        assertEquals(WorldLayerStatuses.FRESH,
            settings.state("aviation", installed = true, nowMs = now).status)
        settings.markUpdated("aviation", now - 61_000L)
        assertEquals(WorldLayerStatuses.LATE,
            settings.state("aviation", installed = true, nowMs = now).status)

        settings.markUpdated("wiki", now - 86_400_000L)
        assertEquals(WorldLayerStatuses.FRESH,
            settings.state("wiki", installed = true, nowMs = now).status)
        settings.markUpdated("wiki", now - 86_401_000L)
        assertEquals(WorldLayerStatuses.LATE,
            settings.state("wiki", installed = true, nowMs = now).status)

        val notInstalled = settings.state("aviation", installed = false, nowMs = now)
        assertEquals(WorldLayerStatuses.UNAVAILABLE, notInstalled.status)

        val unknown = settings.state("unknown", installed = true, nowMs = now)
        assertEquals(WorldLayerStatuses.UNAVAILABLE, unknown.status)
    }

    @Test fun everyLayerDeclaresItsMaxAge() {
        assertEquals(listOf(60L, 300L, 1_800L, 900L, 7_200L, 86_400L),
            WorldLayerCatalog.ALL.map { it.maxAgeSeconds })
        assertEquals(listOf("aviation", "maritime", "energy", "notam", "satellite", "wiki"),
            WorldLayerCatalog.ALL.map { it.id })
        assertTrue(WorldLayerCatalog.NOTAM.needsKey)
        assertFalse(WorldLayerCatalog.AVIATION.needsKey)

        val settings = WorldLayerSettings(MemStores(), MemSecrets())
        settings.markUpdated("maritime", now - 301_000L)
        val late = settings.state("maritime", installed = true, nowMs = now)
        assertEquals(300L, late.maxAgeSeconds)
        assertEquals(301L, late.ageSeconds)
        assertEquals(WorldLayerStatuses.LATE, late.status)
    }

    @Test fun snapshotKeepsCatalogOrderAndInstallation() {
        val settings = WorldLayerSettings(MemStores(), MemSecrets())
        settings.setEnabled("energy", true)
        settings.markUpdated("energy", now)
        val all = settings.snapshot(setOf("energy"), now)
        assertEquals(6, all.size)
        assertEquals(WorldLayerCatalog.ALL.map { it.id }, all.map { it.id })
        assertTrue(all.first { it.id == "energy" }.enabled)
        assertEquals(WorldLayerStatuses.FRESH, all.first { it.id == "energy" }.status)
        assertEquals(WorldLayerStatuses.UNAVAILABLE, all.first { it.id == "aviation" }.status)
    }
}

private class MemSecrets : WorldSecretStore {
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

private class MemStores : KeyValueStores {
    private val stores = mutableMapOf<String, MemStore>()

    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { MemStore() }
}

private class MemStore : KeyValueStore {
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
