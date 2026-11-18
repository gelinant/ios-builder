package app.vela.ios.search

import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class QuickChipsTest {
    @Test fun theDefaultSetIsAndroidCatalogInItsOrder() {
        val chips = QuickChips.catalog()
        assertEquals(16, chips.size)
        assertEquals(
            listOf("Restaurants", "Coffee", "Gas station", "Groceries", "Things to do", "Hotels", "Bars"),
            chips.take(7).map { it.key },
        )
        assertEquals(QuickChips.KEYS, chips.map { it.key })
        assertEquals("cat_post_offices", chips.first { it.key == "Post office" }.labelKey)
        assertEquals("Gas station", chips.first { it.key == QuickChips.FUEL_KEY }.query)
    }

    @Test fun theFuelQueryFollowsTheRegionWithoutChangingTheKey() {
        val petrol = QuickChips.catalog(fuelQuery = "Petrol station")
        assertEquals("Petrol station", petrol.first { it.key == QuickChips.FUEL_KEY }.query)
        assertEquals(QuickChips.FUEL_KEY, petrol.first { it.labelKey == "cat_gas" }.key)
    }

    @Test fun theStoreStartsOnTheDefaultSet() {
        val store = QuickChipsStore(MemStores())
        assertEquals(QuickChips.KEYS, store.arranged())
        assertEquals(QuickChips.KEYS, store.visible())
        assertFalse(store.state.value.customized)
    }

    @Test fun switchingAChipOffHidesItFromTheRowButKeepsItsPlace() {
        val stores = MemStores()
        val store = QuickChipsStore(stores)
        store.setShown("Coffee", false)

        assertEquals(QuickChips.KEYS, store.arranged())
        assertFalse("Coffee" in store.visible())
        assertTrue("Restaurants" in store.visible())
        assertEquals("Coffee", QuickChips.moved(store.arranged(), "Coffee", -1).first())

        // Android's key and separator, so a build that reads the same preference agrees.
        assertEquals("Coffee", stores.open("vela_settings").getString(QuickChipsStore.HIDDEN_KEY, null))
        assertTrue(store.state.value.customized)

        store.setShown("Coffee", true)
        assertTrue("Coffee" in store.visible())
        assertFalse(store.state.value.customized)
    }

    @Test fun theOrderPersistsAcrossStoreInstances() {
        val stores = MemStores()
        val first = QuickChipsStore(stores)
        first.move("Coffee", -1)
        first.move("Parking", 2)

        val saved = stores.open("vela_settings").getString(QuickChipsStore.ORDER_KEY, null)
        assertEquals(
            listOf("Coffee", "Restaurants", "Gas station", "Groceries", "Things to do", "Hotels", "Bars",
                "EV charging station", "Pharmacy", "ATMs", "Parking", "Parks", "Hospitals", "Banks",
                "Post office", "Campgrounds"),
            saved?.split("|"),
        )

        val second = QuickChipsStore(stores)
        assertEquals(saved?.split("|"), second.arranged())
        assertEquals("Coffee", second.visible().first())
        assertEquals(
            listOf("Restaurants", "Gas station", "Groceries", "Things to do", "Hotels", "Bars",
                "EV charging station", "Pharmacy", "ATMs", "Parking", "Parks", "Hospitals", "Banks",
                "Post office", "Campgrounds"),
            second.visible().drop(1),
        )
    }

    @Test fun movingHoldsTheEndsAndIgnoresAnAbsentKey() {
        val key = "Restaurants"
        assertEquals(QuickChips.KEYS, QuickChips.moved(QuickChips.KEYS, key, -1))
        assertEquals(QuickChips.KEYS, QuickChips.moved(QuickChips.KEYS, "Nope", 1))
        assertEquals("Coffee", QuickChips.moved(QuickChips.KEYS, "Coffee", -1).first())
        assertEquals("Gas station", QuickChips.moved(QuickChips.KEYS, "Gas station", -1)[1])
    }

    @Test fun anUnknownSavedKeyIsSkippedAndACompanionTakesTheEnd() {
        assertEquals(
            listOf("Coffee", "Restaurants", "Gas station"),
            QuickChips.arrange(listOf("Restaurants", "Coffee", "Gas station"), listOf("Coffee", "Withdrawn")),
        )
        assertEquals(
            listOf("Coffee", "Restaurants", "Gas station", "Parking"),
            QuickChips.arrange(listOf("Restaurants", "Coffee", "Gas station", "Parking"), listOf("Coffee")),
        )
    }

    @Test fun resetClearsBothKeysAndTheDefaultOrderComesBack() {
        val stores = MemStores()
        val store = QuickChipsStore(stores)
        store.move("Parking", -3)
        store.setShown("Bars", false)
        assertTrue(store.state.value.customized)

        store.reset()
        assertEquals(QuickChips.KEYS, store.arranged())
        assertEquals(QuickChips.KEYS, store.visible())
        assertFalse(store.state.value.customized)
        assertEquals(null, stores.open("vela_settings").getString(QuickChipsStore.ORDER_KEY, null))
        assertEquals(null, stores.open("vela_settings").getString(QuickChipsStore.HIDDEN_KEY, null))
    }
}

/** In-memory [KeyValueStores] with Android's synchronous apply, as the settings tests use. */
private class MemStores : KeyValueStores {
    private val stores = mutableMapOf<String, MemStore>()
    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { MemStore() }
}

private class MemStore : KeyValueStore {
    val values = mutableMapOf<String, Any>()

    override fun contains(key: String) = key in values
    override fun getString(key: String, default: String?) = values[key] as? String ?: default
    override fun getLong(key: String, default: Long) = values[key] as? Long ?: default
    override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
    override fun getFloat(key: String, default: Float) = values[key] as? Float ?: default
    override fun keys(): Set<String> = values.keys
    override fun edit(): KeyValueEditor = Editor()

    private inner class Editor : KeyValueEditor {
        private var clear = false
        private val changes = mutableListOf<Pair<String, Any?>>()

        override fun putString(key: String, value: String?) = put(key, value)
        override fun putLong(key: String, value: Long) = put(key, value)
        override fun putInt(key: String, value: Int) = put(key, value)
        override fun putBoolean(key: String, value: Boolean) = put(key, value)
        override fun putFloat(key: String, value: Float) = put(key, value)
        override fun remove(key: String) = put(key, null)
        override fun clear(): KeyValueEditor = also { clear = true }

        private fun put(key: String, value: Any?): KeyValueEditor = also { changes += key to value }

        override fun apply() {
            if (clear) values.clear()
            for ((key, value) in changes) {
                if (value == null) values.remove(key) else values[key] = value
            }
        }

        override fun commit(): Boolean {
            apply()
            return true
        }
    }
}
