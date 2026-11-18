package app.vela.ios.map

import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** G-2: the stored projection and the z1 floor, without a map or a network. */
class GlobeSettingsTest {
    @Test fun defaultProjectionIsMercatorUnderTheStableKey() {
        val store = GlobeSettingsStore(GlobeMemStores())
        assertEquals("map_projection", GlobeProjection.KEY)
        assertEquals("mercator", store.projection)
        assertFalse(GlobeProjection.isGlobe(store.projection))
    }

    @Test fun globeProjectionSurvivesANewProcess() {
        val stores = GlobeMemStores()
        val first = GlobeSettingsStore(stores)
        first.setProjection("globe")
        assertEquals("globe", first.projection)

        val second = GlobeSettingsStore(stores)
        assertEquals("globe", second.projection)
        assertTrue(GlobeProjection.isGlobe(second.projection))
    }

    @Test fun unknownValuesFallBackToMercator() {
        val store = GlobeSettingsStore(GlobeMemStores())
        store.setProjection("orthographic")
        assertEquals("mercator", store.projection)
    }

    @Test fun globeClampRaisesAnyZoomBelowOne() {
        val store = GlobeSettingsStore(GlobeMemStores())
        store.setProjection("globe")
        assertEquals(1.0, store.minimumZoom())
        assertEquals(1.0, store.clampZoom(0.4))
        assertEquals(1.0, store.clampZoom(-0.09))
        assertEquals(3.5, store.clampZoom(3.5))
    }

    @Test fun mercatorKeepsTheWholeZoomRange() {
        val store = GlobeSettingsStore(GlobeMemStores())
        assertEquals(0.0, store.minimumZoom())
        assertEquals(0.4, store.clampZoom(0.4))
        assertEquals(0.0, store.clampZoom(-0.09))
        assertEquals(0.0, GlobeProjection.clampZoom(0.0, "mercator"))
        assertEquals(1.0, GlobeProjection.clampZoom(0.0, "globe"))
    }
}

private class GlobeMemStores : KeyValueStores {
    private val stores = mutableMapOf<String, GlobeMemStore>()

    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { GlobeMemStore() }
}

private class GlobeMemStore : KeyValueStore {
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

        override fun putString(key: String, value: String?): KeyValueEditor = applyChange(key, value)
        override fun putLong(key: String, value: Long): KeyValueEditor = applyChange(key, value)
        override fun putInt(key: String, value: Int): KeyValueEditor = applyChange(key, value)
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = applyChange(key, value)
        override fun putFloat(key: String, value: Float): KeyValueEditor = applyChange(key, value)
        override fun remove(key: String): KeyValueEditor = applyChange(key, null)
        override fun clear(): KeyValueEditor { clear = true; return this }

        private fun applyChange(key: String, value: Any?): KeyValueEditor {
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
