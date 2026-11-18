package app.vela.ios.settings

import app.vela.core.data.ClockFormat
import app.vela.core.data.CategoryFilter
import app.vela.core.data.LowDataMode
import app.vela.core.data.LowRamMode
import app.vela.core.data.NoGoogle
import app.vela.core.i18n.FrNavStrings
import app.vela.core.i18n.HeNavStrings
import app.vela.core.i18n.NavStringsRegistry
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

class SettingsStoreTest {
    @AfterTest fun resetHolders() {
        NoGoogle.enabled = false
        ClockFormat.use24h = false
        LowDataMode.enabled = false
        LowRamMode.enabled = false
        CategoryFilter.enabled = false
        ContentPolicy.reset()
        NavStringsRegistry.setLanguage("en")
    }

    @Test fun defaultsFollowTheDevice() {
        val store = SettingsStore(MemStores(), deviceUse24h = true, deviceImperial = true)
        store.start()
        assertEquals(SettingsState(imperial = true, use24h = true), store.state.value)
        assertTrue(ClockFormat.use24h)
        assertFalse(NoGoogle.enabled)
    }

    @Test fun choicesPersistAcrossStoreInstances() {
        val stores = MemStores()
        val first = SettingsStore(stores, deviceUse24h = false, deviceImperial = false)
        first.start()
        first.setLanguage("fr")
        first.setUnits("imperial")
        first.setClockMode("24")
        stores.open("vela_settings").edit().putBoolean(SettingsStore.GOOGLE_DISABLED_KEY, true).apply()

        val second = SettingsStore(stores, deviceUse24h = false, deviceImperial = false)
        second.start()
        assertEquals("fr", second.state.value.languageTag)
        assertEquals("imperial", second.state.value.units)
        assertTrue(second.imperial)
        assertEquals("24", second.state.value.clockMode)
        assertTrue(second.use24h)
        assertTrue(ClockFormat.use24h)
        assertTrue(NoGoogle.enabled)
        assertSame(FrNavStrings, NavStringsRegistry.current())
    }

    @Test fun launchLanguageWinsWithoutBeingPersisted() {
        val stores = MemStores()
        stores.open("vela_settings").edit().putString("app_language", "fr").apply()
        val store = SettingsStore(
            stores, deviceUse24h = false, deviceImperial = false,
            systemTag = { "en-US" }, languageOverride = "he",
        )
        store.start()
        assertEquals("he", store.state.value.languageTag)
        assertSame(HeNavStrings, NavStringsRegistry.current())
        assertEquals("fr", stores.open("vela_settings").getString("app_language", ""))
    }

    @Test fun systemLanguageDrivesNavStrings() {
        val store = SettingsStore(
            MemStores(), deviceUse24h = false, deviceImperial = false,
            systemTag = { "fr-FR" },
        )
        store.start()
        assertEquals("", store.state.value.languageTag)
        assertSame(FrNavStrings, NavStringsRegistry.current())
    }

    @Test fun contentPolicyPersistsAndReachesTheHoldersBeforeStart() {
        val stores = MemStores()
        val first = SettingsStore(stores, deviceUse24h = false, deviceImperial = false)
        first.start()
        first.setLowDataMode(true)
        first.setLowRamMode(true)
        first.setPlaceContent(ContentPolicy.TILES)
        first.setShowReviews(false)
        first.setLoadPhotos(false)
        first.setPhotosWifiOnly(true)
        first.setPhotoQuality(ContentPolicy.QUALITY_LOW)
        first.setPhotoCacheMb(50)
        first.setFullPlaceLoad(true)
        first.setDetailsRetry(false)
        first.setHideAdult(true)
        first.setHideExternalLinks(true)
        first.setRedactPlacesInExports(true)
        assertTrue(LowDataMode.enabled)
        assertTrue(LowRamMode.enabled)
        assertTrue(CategoryFilter.enabled)

        // A new process: start() applies every holder before the first request.
        LowDataMode.enabled = false
        LowRamMode.enabled = false
        CategoryFilter.enabled = false
        ContentPolicy.reset()
        val second = SettingsStore(stores, deviceUse24h = false, deviceImperial = false)
        second.start()
        val s = second.state.value
        assertTrue(s.lowDataMode)
        assertTrue(s.lowRamMode)
        assertEquals(ContentPolicy.TILES, s.placeContent)
        assertFalse(s.showReviews)
        assertFalse(s.loadPhotos)
        assertTrue(s.photosWifiOnly)
        assertEquals(ContentPolicy.QUALITY_LOW, s.photoQuality)
        assertEquals(50, s.photoCacheMb)
        assertTrue(s.fullPlaceLoad)
        assertFalse(s.detailsRetry)
        assertTrue(s.hideAdult)
        assertTrue(s.hideExternalLinks)
        assertTrue(s.redactPlacesInExports)
        assertTrue(LowDataMode.enabled)
        assertTrue(LowRamMode.enabled)
        assertTrue(CategoryFilter.enabled)
        assertTrue(ContentPolicy.tilesOnly)
        assertFalse(ContentPolicy.showReviews)
        assertFalse(ContentPolicy.loadPhotos)
        assertTrue(ContentPolicy.redactPlacesInExports)
    }

    @Test fun contentKeysMatchAndroidAndClampTheCache() {
        val stores = MemStores()
        stores.open("vela_settings").edit()
            .putBoolean("low_data_mode", true)
            .putBoolean("low_ram_mode", true)
            .putBoolean("show_reviews", false)
            .putBoolean("load_photos", false)
            .putString("place_content", "nonsense")
            .putInt("photo_cache_mb", 9_999)
            .apply()
        val store = SettingsStore(stores, deviceUse24h = false, deviceImperial = false)
        store.start()
        val s = store.state.value
        assertTrue(s.lowDataMode)
        assertTrue(s.lowRamMode)
        assertFalse(s.showReviews)
        assertFalse(s.loadPhotos)
        assertEquals(ContentPolicy.FULL, s.placeContent)
        assertEquals(ContentPolicy.CACHE_MB_MAX, s.photoCacheMb)
    }

    @Test fun languageAliasesMatchAndroidAndTheCatalog() {
        assertEquals("pt", SettingsStore.normalizeLanguage("pt-PT"))
        assertEquals("pt-BR", SettingsStore.normalizeLanguage("pt-BR"))
        assertEquals("zh", SettingsStore.normalizeLanguage("zh-Hans"))
        assertEquals("zh-TW", SettingsStore.normalizeLanguage("zh-Hant-TW"))
        assertEquals("he", SettingsStore.normalizeLanguage("iw"))
        assertEquals("en-GB", SettingsStore.normalizeLanguage("en_GB"))
        assertEquals(null, SettingsStore.normalizeLanguage("not-a-locale"))
    }
}

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
