package app.vela.ios.offline

import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NormalForm
import app.vela.core.platform.SqlCursor
import app.vela.core.platform.SqlDb
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import app.vela.ios.config.MemoryFiles
import app.vela.ios.search.FakeLocale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The fixture pipeline end to end at the store seam. The manifests used by the Debug UI fixtures
 * name their bodies plainly while the app bundle stores them under `offline-fixture-`; the plan
 * rewriter must map every piece and every delta before a transfer starts, or the fixture host has
 * nothing to serve and the sheet hangs at zero pieces.
 */
class OfflineFixtureTest {
    @Test fun everyFixturePlanUrlReachesTheDownloaderRewritten() = runBlocking {
        val files = MemoryFiles()
        val urls = mutableListOf<String>()
        val store = store(files, MemoryKv(), RecordingDownloader(urls))
        store.useFixtureCatalogs(
            routingJson = routing, packsJson = packs, placesJson = places, mapsJson = maps,
            worldUrl = "https://offline.fixture.invalid/world.pmtiles",
            glyphUrl = "https://offline.fixture.invalid/map-fonts.zip",
        )
        val plan = PendingRegionDownload(
            record = InstalledRegion("monaco", packId = "monaco"),
            assets = listOf(
                OfflineAssetPlan(
                    "monaco", OfflineStore.KIND_PACK,
                    "https://offline.fixture.invalid/pack-v1.zip",
                    "/nobackup/offline/poipacks/monaco.db", rev = 1, sizeMb = 1,
                ),
            ),
        )
        files.writeTextAtomic(
            store.rootPath + "/region-download.json",
            Json.encodeToString(PendingRegionDownload.serializer(), plan),
        )

        store.start()
        withTimeout(10_000) { while (urls.isEmpty()) delay(20) }

        assertEquals(
            setOf("https://offline.fixture.invalid/offline-fixture-pack-v1.zip"),
            urls.toSet(),
            "a plan URL bypassed the fixture rewriter",
        )
    }

    @Test fun theRewriterCoversEveryPieceAndDeltaNameAndIsIdempotent() {
        assertEquals(
            "https://offline.fixture.invalid/offline-fixture-pack-v1.zip",
            OfflineFixtureUrls.rewrite("https://offline.fixture.invalid/pack-v1.zip"),
        )
        assertEquals(
            "https://offline.fixture.invalid/offline-fixture-places-v1-to-v2.vpatch",
            OfflineFixtureUrls.rewrite("https://offline.fixture.invalid/places-v1-to-v2.vpatch"),
        )
        assertEquals(
            "https://offline.fixture.invalid/offline-fixture-pack-delta.zip",
            OfflineFixtureUrls.rewrite("https://offline.fixture.invalid/pack-delta.zip"),
        )
        assertEquals(
            "https://offline.fixture.invalid/offline-fixture-pack-v1.zip",
            OfflineFixtureUrls.rewrite(
                "https://offline.fixture.invalid/offline-fixture-pack-v1.zip"),
        )
        assertEquals(
            "https://mirror.example/pack-v1.zip",
            OfflineFixtureUrls.rewrite("https://mirror.example/pack-v1.zip"),
            "a real URL is never rewritten",
        )
    }

    @Test fun areaSwitchesPersistAndThePlanHonoursThem() = runBlocking {
        val files = MemoryFiles()
        val preferences = MemoryKv()
        val first = store(files, preferences, RecordingDownloader(mutableListOf()))
        first.useFixtureCatalogs(routingJson = routing, packsJson = packs, placesJson = places, mapsJson = maps)
        first.start()
        first.setAreaCameras(false)
        first.setAreaAddresses(false)
        assertFalse(first.state.value.areaCameras)
        assertFalse(first.state.value.areaAddresses)
        assertFalse(first.areaPreferences().cameras)
        assertFalse(first.areaPreferences().addresses)

        // A new store over the same settings is what a relaunch sees.
        val second = store(files, preferences, RecordingDownloader(mutableListOf()))
        second.useFixtureCatalogs(routingJson = routing, packsJson = packs, placesJson = places, mapsJson = maps)
        second.start()
        assertFalse(second.state.value.areaCameras, "the camera switch did not persist")
        assertFalse(second.state.value.areaAddresses, "the address switch did not persist")

        val plan = second.planArea(south = 43.70, west = 7.38, north = 43.78, east = 7.46)
        assertEquals("monaco", plan.regionId)
        assertFalse(plan.camerasIncluded)
        assertFalse(plan.addressesIncluded)
    }

    @Test fun thePlacesSwitchStillDropsThePackAndPlaceArchives() = runBlocking {
        val files = MemoryFiles()
        val store = store(files, MemoryKv(), RecordingDownloader(mutableListOf()))
        store.useFixtureCatalogs(routingJson = routing, packsJson = packs, placesJson = places, mapsJson = maps)
        store.start()
        store.setAreaPlaces(false)
        val plan = store.planArea(south = 43.70, west = 7.38, north = 43.78, east = 7.46)
        assertFalse(plan.placesIncluded)
        assertTrue(plan.camerasIncluded)
        assertTrue(plan.addressesIncluded)
    }

    private fun store(
        files: MemoryFiles,
        keyValues: KeyValueStores,
        downloader: app.vela.ios.offline.OfflineDownloadClient,
    ) = OfflineStore(
        core = CoreGraph(
            log = object : Log {
                override fun isLoggable(tag: String, level: LogLevel) = false
                override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
            },
            clock = object : Clock {
                override fun nowMillis() = 0L
                override fun elapsedRealtimeMillis() = 0L
                override fun monotonicNanos() = 0L
            },
            keyValues = keyValues,
            files = files,
            http = object : VelaHttp {
                override fun execute(
                    request: app.vela.core.platform.HttpRequest,
                    callback: (app.vela.core.platform.HttpResponse?, Throwable?) -> Unit,
                ): Cancellable {
                    callback(null, IllegalStateException("no network in this test"))
                    return Cancellable {}
                }
            },
            text = object : TextNormalizer {
                override fun normalize(text: String, form: NormalForm) = text
            },
            locale = FakeLocale("en-US"),
        ),
        sql = NoSql,
        scope = CoroutineScope(Dispatchers.Unconfined),
        downloader = downloader,
    )

    private class RecordingDownloader(private val urls: MutableList<String>) : OfflineDownloadClient {
        override fun start(
            id: String,
            kind: String,
            url: String,
            targetPath: String,
            onProgress: (receivedBytes: Long, totalBytes: Long) -> Unit,
            onComplete: (error: String?) -> Unit,
        ): Cancellable {
            urls += url
            onComplete("network")
            return Cancellable {}
        }
    }

    private class MemoryKv : KeyValueStores {
        private val stores = mutableMapOf<String, MemoryStore>()
        override fun open(name: String): KeyValueStore = stores.getOrPut(name) { MemoryStore() }
    }

    private class MemoryStore : KeyValueStore {
        private val values = mutableMapOf<String, Any?>()
        override fun contains(key: String) = key in values
        override fun getString(key: String, default: String?) = values[key] as? String ?: default
        override fun getLong(key: String, default: Long) = values[key] as? Long ?: default
        override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
        override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
        override fun getFloat(key: String, default: Float) = values[key] as? Float ?: default
        override fun keys(): Set<String> = values.keys
        override fun edit(): KeyValueEditor = Editor(values)
    }

    private class Editor(private val values: MutableMap<String, Any?>) : KeyValueEditor {
        private val pending = mutableMapOf<String, Any?>()
        override fun putString(key: String, value: String?): KeyValueEditor {
            pending[key] = value
            return this
        }
        override fun putLong(key: String, value: Long): KeyValueEditor {
            pending[key] = value
            return this
        }
        override fun putInt(key: String, value: Int): KeyValueEditor {
            pending[key] = value
            return this
        }
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor {
            pending[key] = value
            return this
        }
        override fun putFloat(key: String, value: Float): KeyValueEditor {
            pending[key] = value
            return this
        }
        override fun remove(key: String): KeyValueEditor {
            pending[key] = null
            return this
        }
        override fun clear(): KeyValueEditor {
            values.clear()
            pending.clear()
            return this
        }
        override fun apply() {
            for ((key, value) in pending) {
                if (value == null) values.remove(key) else values[key] = value
            }
            pending.clear()
        }
        override fun commit(): Boolean {
            apply()
            return true
        }
    }

    /** The store only opens SQLite for a download body the fake never produces. */
    private object NoSql : SqlDbs {
        override fun open(
            name: String,
            version: Int,
            onCreate: (SqlDb) -> Unit,
            onUpgrade: (SqlDb, Int, Int) -> Unit,
        ): SqlDb = NoDb
        override fun openReadOnly(path: String): SqlDb = NoDb
    }

    private object NoDb : SqlDb {
        override fun execute(sql: String, args: List<Any?>) {}
        override fun query(sql: String, args: List<Any?>, row: (SqlCursor) -> Unit) {}
        override fun <T> transaction(block: () -> T): T = block()
        override fun close() {}
    }

    private companion object {
        private const val BBOX = "[43.72,7.40,43.76,7.44]"
        private val routing =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/obf","sizeMb":1,"bbox":$BBOX}]}"""
        private val packs =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/pack-v1.zip","sizeMb":1,"installedMb":1,"bbox":$BBOX,"rev":1,"counts":{"poi":1,"streetname":1,"addr":1,"streetpt":1}}]}"""
        private val places =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/places-v1.pmtiles","sizeMb":1,"bbox":$BBOX,"rev":1}]}"""
        private val maps =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/basemap-v1.pmtiles","sizeMb":1,"bbox":$BBOX,"rev":1}]}"""
    }
}
