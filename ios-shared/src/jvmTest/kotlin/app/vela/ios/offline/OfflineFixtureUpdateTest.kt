package app.vela.ios.offline

import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.FileEntry
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NormalForm
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.SqlCursor
import app.vela.core.platform.SqlDb
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import app.vela.ios.search.FakeLocale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * The Debug fixture's update gate, at the seam the UI scenario reads: an installed rev 1 makes an
 * update plan empty, and loading the rev 2 catalogs must offer exactly one update. The first
 * preparation of a store is one-shot, so a second model cannot reset a region under a scenario.
 */
class OfflineFixtureUpdateTest {
    @Test fun revisionTwoOffersTheInstalledRegionOnce() = runBlocking {
        val files = ByteFiles()
        val record = InstalledRegion("monaco", packId = "monaco")
        files.writeText(
            "${files.noBackupDir}/offline/regions/monaco.json",
            Json.encodeToString(InstalledRegion.serializer(), record),
        )
        files.writeText(
            "${files.noBackupDir}/offline/revs.json",
            Json.encodeToString(
                InstalledRevisions.serializer(),
                InstalledRevisions().with(OfflineStore.KIND_PACK, "monaco", 1),
            ),
        )
        val store = store(files)
        store.useFixtureCatalogs(
            routingJson = routing, packsJson = packs(1), placesJson = places(1),
            mapsJson = maps(1), worldUrl = null, glyphUrl = null,
        )
        store.start()
        delay(100)
        assertTrue(
            store.fixtureSummary().contains("manifest=1 installed=1 updatable=0"),
            "rev 1 must not offer an update: ${store.fixtureSummary()}",
        )
        store.useFixtureCatalogs(
            routingJson = routing, packsJson = packs(2), placesJson = places(2),
            mapsJson = maps(2), worldUrl = null, glyphUrl = null,
        )
        delay(100)
        assertTrue(
            store.fixtureSummary().contains("manifest=2 installed=1 updatable=1"),
            "the rev 2 manifest did not offer the installed region: ${store.fixtureSummary()}",
        )
        assertTrue(store.state.value.regions.single().updatable)
        assertTrue(!store.fixtureInstallDone(), "a store is prepared only by its caller")
        store.markFixtureInstallDone()
        assertTrue(store.fixtureInstallDone(), "the one-shot fixture mark did not stick")
        assertTrue(store.fixturePrepared(), "the process preparation mark is missing")
        val second = store(files)
        assertTrue(second.fixturePrepared(), "a second store must see the process preparation")
        assertTrue(!second.fixtureReady(), "a second store still has to load the catalogs")
    }

    private fun store(files: ByteFiles) = OfflineStore(
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
            keyValues = object : KeyValueStores {
                private val stores = mutableMapOf<String, MemStore>()
                override fun open(name: String) = stores.getOrPut(name) { MemStore() }
            },
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
            text = object : TextNormalizer { override fun normalize(text: String, form: NormalForm) = text },
            locale = FakeLocale("en-US"),
        ),
        sql = object : SqlDbs {
            override fun open(
                name: String, version: Int,
                onCreate: (SqlDb) -> Unit, onUpgrade: (SqlDb, Int, Int) -> Unit,
            ): SqlDb = NoDb
            override fun openReadOnly(path: String): SqlDb = NoDb
        },
        scope = CoroutineScope(Dispatchers.Unconfined),
        downloader = object : OfflineDownloadClient {
            override fun start(
                id: String, kind: String, url: String, targetPath: String,
                onProgress: (Long, Long) -> Unit, onComplete: (String?) -> Unit,
            ): Cancellable {
                onComplete("network")
                return Cancellable {}
            }
        },
    )

    class ByteFiles : PlatformFiles {
        private val map = mutableMapOf<String, ByteArray>()
        override val filesDir get() = "/files"
        override val cacheDir get() = "/cache"
        override val noBackupDir get() = "/nobackup"
        override fun exists(path: String) = path in map
        override fun isDirectory(path: String) = map.keys.any { it.startsWith("$path/") }
        override fun size(path: String) = map[path]?.size?.toLong() ?: 0L
        override fun lastModifiedMillis(path: String) = 0L
        override fun list(path: String): List<FileEntry>? {
            val prefix = "$path/"
            return map.keys.filter { it.startsWith(prefix) }.mapNotNull { key ->
                val name = key.removePrefix(prefix)
                if ('/' in name) null
                else FileEntry(name, key, false, map.getValue(key).size.toLong(), 0L)
            }
        }
        override fun mkdirs(path: String) = true
        override fun readBytes(path: String) = map[path] ?: throw java.io.IOException("missing $path")
        override fun readText(path: String) = readBytes(path).decodeToString()
        override fun writeBytes(path: String, bytes: ByteArray) { map[path] = bytes }
        override fun writeText(path: String, text: String) { map[path] = text.encodeToByteArray() }
        override fun writeTextAtomic(path: String, text: String) { map[path] = text.encodeToByteArray() }
        override fun rename(from: String, to: String) = map.remove(from)?.let { map[to] = it; true } ?: false
        override fun delete(path: String) = map.remove(path) != null
        override fun deleteRecursively(path: String): Boolean {
            map.keys.filter { it == path || it.startsWith("$path/") }.forEach { map.remove(it) }
            return true
        }
    }

    private class MemStore : KeyValueStore {
        private val values = mutableMapOf<String, Any?>()
        override fun contains(key: String) = key in values
        override fun getString(key: String, default: String?) = values[key] as? String ?: default
        override fun getLong(key: String, default: Long) = values[key] as? Long ?: default
        override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
        override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
        override fun getFloat(key: String, default: Float) = values[key] as? Float ?: default
        override fun keys(): Set<String> = values.keys
        override fun edit(): KeyValueEditor = object : KeyValueEditor {
            override fun putString(key: String, value: String?) = this
            override fun putLong(key: String, value: Long) = this
            override fun putInt(key: String, value: Int) = this
            override fun putBoolean(key: String, value: Boolean) = this
            override fun putFloat(key: String, value: Float) = this
            override fun remove(key: String) = this
            override fun clear() = this
            override fun apply() {}
            override fun commit() = true
        }
    }

    private object NoDb : SqlDb {
        override fun execute(sql: String, args: List<Any?>) {}
        override fun query(sql: String, args: List<Any?>, row: (SqlCursor) -> Unit) {}
        override fun <T> transaction(block: () -> T): T = block()
        override fun close() {}
    }

    private companion object {
        const val BBOX = "[43.72,7.40,43.76,7.44]"
        const val routing =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/obf","sizeMb":1,"bbox":$BBOX}]}"""
        fun packs(rev: Int) =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/pack-v$rev.zip","sizeMb":1,"installedMb":1,"bbox":$BBOX,"rev":$rev,"counts":{"poi":1}}]}"""
        fun places(rev: Int) =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/places-v$rev.pmtiles","sizeMb":1,"bbox":$BBOX,"rev":$rev}]}"""
        fun maps(rev: Int) =
            """{"regions":[{"id":"monaco","name":"Monaco (fixture)","url":"https://offline.fixture.invalid/basemap-v$rev.pmtiles","sizeMb":1,"bbox":$BBOX,"rev":$rev}]}"""
    }
}
