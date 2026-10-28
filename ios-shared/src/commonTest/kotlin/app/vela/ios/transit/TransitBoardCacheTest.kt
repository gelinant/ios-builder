package app.vela.ios.transit

import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitMode
import app.vela.core.platform.FileEntry
import app.vela.core.platform.PlatformFiles
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The offline board: last successful board per stop, bounded, expiring, and never live. */
@OptIn(ExperimentalCoroutinesApi::class)
class TransitBoardCacheTest {
    private var nowMs = 1_800_000_000_000L
    private val nowSec = nowMs / 1000L
    private val files = TreeFiles()

    private fun target(id: String = "stop-1") =
        TransitBoardTarget(stopId = id, name = "Ferry Building", lat = 37.7955, lng = -122.3937)

    private fun board(name: String = "Ferry Building", live: Boolean = true): StopDepartures =
        StopDepartures(
            stationName = name,
            lines = listOf(
                StopDepartureLine(
                    label = "14", mode = TransitMode.BUS, headsign = "Ferry Plaza", colorHex = "#0f6cbd",
                    upcoming = listOf(
                        StopDeparture("9:41 AM", nowSec + 180, realtime = live),
                        StopDeparture("9:49 AM", nowSec + 660, realtime = false),
                    ),
                ),
            ),
        )

    private fun cache() = TransitBoardCache(files)

    @Test fun savedBoardComesBackWithoutLiveMarks() {
        val cache = cache()
        cache.save(target(), board(), nowMs)
        val loaded = assertNotNull(cache.load(target(), nowMs + 1_000L))
        assertEquals(nowMs, loaded.fetchedAtMillis)
        assertEquals("Ferry Building", loaded.board.stationName)
        assertEquals(listOf("14"), loaded.board.lines.map { it.label })
        assertEquals(listOf(false, false), loaded.board.lines[0].upcoming.map { it.realtime })
    }

    @Test fun anExpiredEntryIsDeletedInsteadOfShown() {
        val cache = cache()
        cache.save(target(), board(), nowMs)
        val past = nowMs + TransitBoardCache.MAX_AGE_MILLIS + 1L
        assertNull(cache.load(target(), past))
        assertEquals(0, files.list("/files/${TransitBoardCache.DIR}").orEmpty().count { !it.isDirectory })
    }

    @Test fun aBoardWhoseRunsHaveLeftIsNotShown() {
        val cache = cache()
        cache.save(target(), board(), nowMs)
        assertNull(cache.load(target(), nowMs + 3L * 60 * 60 * 1000))
    }

    @Test fun theFolderIsBoundedAndTheOldestEntryGoes() {
        val cache = cache()
        val count = TransitBoardCache.MAX_ENTRIES + 8
        for (i in 0 until count) {
            cache.save(target("stop-$i"), board(), nowMs + i * 1_000L)
        }
        val stored = files.list("/files/${TransitBoardCache.DIR}").orEmpty().count { !it.isDirectory }
        assertTrue(stored <= TransitBoardCache.MAX_ENTRIES, "stored $stored")
        assertNull(cache.load(target("stop-0"), nowMs + count * 1_000L), "oldest was not pruned")
        assertNotNull(cache.load(target("stop-${count - 1}"), nowMs + count * 1_000L))
    }

    @Test fun aFailedFeedKeepsTheCachedBoardAndSaysItIsOffline() = runTest {
        val cache = cache()
        cache.save(target(), board(), nowMs)
        val store = TransitBoardStore(
            backgroundScope, { null }, { nowMs }, refreshMillis = 1_000_000L, cache = cache,
        )
        store.openStop("stop-1", "Ferry Building", 37.7955, -122.3937)
        runCurrent()

        val s = store.state.value
        assertTrue(s.open)
        assertFalse(s.loading)
        assertTrue(s.offline, "a board shown without a feed answer is offline")
        assertEquals(nowMs, s.cachedAtMillis)
        assertEquals(nowMs, s.fetchedAtMillis)
        assertEquals(2, s.departureCount)
        assertEquals(0, s.realtimeCount, "the cache must never fake a live mark")
        assertNull(s.error)
    }

    @Test fun aLiveAnswerReplacesTheCacheAndAFailureWithoutCacheIsNamed() = runTest {
        val cache = cache()
        cache.save(target(), board(live = true), nowMs)
        var answer: StopDepartures? = board(name = "Ferry Building", live = true)
        val store = TransitBoardStore(
            backgroundScope, { answer }, { nowMs }, refreshMillis = 1_000_000L, cache = cache,
        )
        store.openStop("stop-1", "Ferry Building", 37.7955, -122.3937)
        runCurrent()
        var s = store.state.value
        assertFalse(s.offline)
        assertEquals(1, s.realtimeCount, "a live feed answer keeps its live mark")

        answer = null
        store.refresh()
        runCurrent()
        s = store.state.value
        assertFalse(s.offline, "a previously live board is stale, not relabelled offline")
        assertTrue(s.refreshFailed)
        assertEquals(1, s.realtimeCount)

        val emptyFiles = TreeFiles()
        val emptyStore = TransitBoardStore(
            backgroundScope, { null }, { nowMs }, refreshMillis = 1_000_000L,
            cache = TransitBoardCache(emptyFiles),
        )
        emptyStore.open(37.7955, -122.3937, "Ferry Building")
        runCurrent()
        assertEquals("no_departures", emptyStore.state.value.error)
        assertFalse(emptyStore.state.value.offline)
    }

    @Test fun theOfflineFixtureOpensCacheOnly() = runTest {
        val store = TransitBoardStore(
            backgroundScope, { error("the feed must not be asked") }, { nowMs },
            refreshMillis = 1_000_000L, cache = cache(),
        )
        store.openOfflineFixture(37.7955, -122.3937, "Ferry Building")
        runCurrent()
        val s = store.state.value
        assertTrue(s.offline)
        assertEquals(0, s.realtimeCount)
        assertTrue(s.departureCount >= 2)
        assertEquals(nowMs, s.cachedAtMillis)
    }
}

/** [PlatformFiles] with real folder listings, so the cache's pruning is exercised. */
private class TreeFiles : PlatformFiles {
    private val entries = LinkedHashMap<String, ByteArray>()

    override val filesDir: String get() = "/files"
    override val cacheDir: String get() = "/cache"
    override val noBackupDir: String get() = "/nobackup"

    override fun exists(path: String) = entries.containsKey(path) || isDirectory(path)
    override fun isDirectory(path: String) = entries.keys.any { it.startsWith("$path/") }
    override fun size(path: String) = entries[path]?.size?.toLong() ?: 0L
    override fun lastModifiedMillis(path: String) = 0L

    override fun list(path: String): List<FileEntry>? {
        if (!isDirectory(path)) return null
        return entries.keys
            .filter { it.substringBeforeLast('/') == path }
            .map { FileEntry(it.substringAfterLast('/'), it, false, size(it), 0L) }
    }

    override fun mkdirs(path: String) = true
    override fun readBytes(path: String) = entries[path] ?: throw IllegalStateException("missing $path")
    override fun readText(path: String) = readBytes(path).decodeToString()
    override fun writeBytes(path: String, bytes: ByteArray) { entries[path] = bytes }
    override fun writeText(path: String, text: String) { entries[path] = text.encodeToByteArray() }
    override fun writeTextAtomic(path: String, text: String) { entries[path] = text.encodeToByteArray() }
    override fun delete(path: String): Boolean = entries.remove(path) != null
    override fun deleteRecursively(path: String): Boolean {
        entries.keys.filter { it == path || it.startsWith("$path/") }.forEach { entries.remove(it) }
        return true
    }
    override fun rename(from: String, to: String): Boolean {
        val data = entries.remove(from) ?: return false
        entries[to] = data
        return true
    }
}
