package app.vela.ios.replay

import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.model.distanceTo
import app.vela.core.platform.Clock
import app.vela.core.platform.FileEntry
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.joinPath
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Recording lifecycle, partial recovery, export trim and GPX on the JVM. */
class TripsStoreTest {

    // The fixture street: Davis, California. Points are about 50 m apart.
    private val start = LatLng(38.5449, -121.7405)
    private fun path(count: Int): List<LatLng> =
        List(count) { i -> LatLng(start.lat + i * 0.00045, start.lng) }

    private fun routeOf(points: List<LatLng>) = Route(
        polyline = points,
        legs = listOf(
            RouteLeg(
                2_000.0, 180.0, null,
                listOf(
                    Maneuver(
                        ManeuverType.TURN_RIGHT, "Turn right onto 5th Street", points[1],
                        1_800.0, 170.0, road = "5th Street",
                    ),
                    Maneuver(
                        ManeuverType.ARRIVE, "Arrive at your destination", points.last(),
                        0.0, 0.0,
                    ),
                ),
            ),
        ),
        distanceMeters = 2_000.0,
        durationSeconds = 180.0,
        durationInTrafficSeconds = null,
    )

    private fun record(store: TripsStore, points: List<LatLng>, speedMps: Float = 12f, t0: Long = 1_000_000L) {
        points.forEachIndexed { i, p ->
            store.recordFix(
                latitude = p.lat, longitude = p.lng, t = t0 + i * 1_000L,
                bearingDeg = 0.0, speedMps = speedMps.toDouble(), offRoute = false,
                accuracyM = 5.0, provider = "ios", offRouteHits = 0,
            )
        }
    }

    @Test
    fun recordingKeepsRouteNotesAndStats() {
        VelaDiag.reset()
        val files = TestTripFiles()
        val prefs = TestPrefs()
        val store = TripsStore(files, prefs, TestClock())
        store.recordingEnabled = true
        assertTrue(store.recordingEnabled)

        val points = path(8)
        val id = store.startTrip("Davis errand", points.last(), 1_000_000L)
        assertNotNull(id)
        assertTrue(store.isRecording)
        assertNull(store.startTrip("second", null, 2L), "one drive at a time")

        record(store, points)
        store.saveRoute(routeOf(points), "start")
        store.note("K", "recheck: no usable candidate")

        val saved = assertNotNull(store.finishTrip())
        assertFalse(saved.partial)
        assertEquals(8, saved.fixes)
        assertTrue(saved.distanceM > 300.0, "stats sum the fix steps: ${saved.distanceM}")
        assertEquals(7_000L, saved.durationMs)
        assertFalse(store.isRecording)
        assertNull(store.finishTrip(), "finish is idempotent")

        val list = store.list()
        assertEquals(1, list.size)
        assertEquals("Davis errand", list.first().label)
        val csv = assertNotNull(store.rawCsv(id))
        assertTrue(csv.contains("RP,"))
        assertTrue(csv.contains("K,"))
        assertTrue(csv.contains("Turn right onto 5th Street"))

        val detail = assertNotNull(store.detail(id))
        assertEquals(8, detail.points.size)
        assertEquals(1, detail.routeSegments)
        assertEquals(2, detail.maneuvers)
        assertEquals(0L, detail.points.first().tMs)
        assertTrue(detail.maxSpeedMps > 10.0)
    }

    @Test
    fun settingsPurgeReportsTheSizeAndRemovesEveryTrip() {
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        assertNotNull(store.startTrip("First", null, 1_000_000L))
        record(store, path(6))
        assertNotNull(store.finishTrip())
        assertNotNull(store.startTrip("Second", null, 2_000_000L))
        record(store, path(8), t0 = 2_000_000L)
        assertNotNull(store.finishTrip())

        assertEquals(2, store.list().size)
        assertTrue(store.totalBytes() > 0L, "the purge row shows a real size")
        assertEquals(2, store.deleteAll())
        assertTrue(store.list().isEmpty())
        assertEquals(0L, store.totalBytes())
        assertEquals(0, store.deleteAll(), "an empty purge is a no-op")
    }

    @Test
    fun tooShortADriveIsDiscarded() {
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        val points = path(4)
        assertNotNull(store.startTrip("Too short", null, 5L))
        record(store, points)
        assertNull(store.finishTrip())
        assertTrue(store.list().isEmpty())
        assertTrue(files.snapshot().isEmpty(), "the recording file is deleted, not listed")
    }

    @Test
    fun forceQuitLeavesARecoverablePartialTrip() {
        val files = TestTripFiles()
        val first = TripsStore(files, TestPrefs(), TestClock())
        val points = path(9)
        assertNotNull(first.startTrip("Interrupted", points.last(), 7L))
        record(first, points)
        // No finishTrip: the process dies here and a new store sees the same folder.

        val second = TripsStore(files, TestPrefs(), TestClock())
        val partial = second.list().single()
        assertTrue(partial.partial)
        assertNotNull(second.rawCsv(partial.id), "a partial file is still readable")
        assertNotNull(second.detail(partial.id))
        assertTrue(second.keepPartial(partial.id))
        val kept = second.list().single()
        assertFalse(kept.partial)
        assertEquals(partial.fixes, kept.fixes)
    }

    @Test
    fun renameAndDelete() {
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        val points = path(6)
        val id = assertNotNull(store.startTrip("Old name", points.last(), 9L))
        record(store, points)
        assertNotNull(store.finishTrip())
        assertTrue(store.rename(id, "New name"))
        assertEquals("New name", store.list().single().label)
        assertTrue(store.rename(id, "x,".repeat(90)), "a too-long label is clamped, not rejected")
        assertTrue(store.list().single().label.length <= 80)
        store.delete(id)
        assertTrue(store.list().isEmpty())
    }

    @Test
    fun exportTrimsBothEndsAndDropsTheLabel() {
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        val points = path(120)
        val dest = points.last()
        val id = assertNotNull(store.startTrip("Davis errand", dest, 1_000_000L))
        record(store, points)
        store.note("K", "settings: units imperial")
        assertNotNull(store.finishTrip())

        val preview = assertNotNull(store.previewTrim(id, 200.0))
        assertEquals(120, preview.fixesBefore)
        assertTrue(preview.trimmable)
        assertTrue(preview.fixesAfter in 100..114, "kept ${preview.fixesAfter}")

        val csv = assertNotNull(store.exportScrubbedCsv(id, 200.0))
        val exported = app.vela.core.replay.TripLog.parsePoints(csv.split('\n').filter { it.isNotBlank() })
        assertEquals(preview.fixesAfter, exported.size)
        assertTrue(exported.first().latLng.distanceTo(start) >= 200.0)
        assertTrue(exported.last().latLng.distanceTo(dest) >= 200.0)
        assertFalse(csv.contains("Davis errand"), "the label names a place")
        assertFalse(csv.contains("${dest.lat}"), "the destination is dropped from META")
        assertTrue(csv.contains("settings: units imperial"), "technical notes stay for the whole drive")
        assertEquals(0L, exported.first().t, "times are rebased so no wall clock is published")

        assertNull(store.exportScrubbedCsv(id, 30_000.0), "a trip with no middle is not shared empty")
    }

    @Test
    fun gpxHoldsOnlyTheTrimmedTrace() {
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        val points = path(60)
        val id = assertNotNull(store.startTrip("Home", points.last(), 1_000_000L))
        record(store, points)
        assertNotNull(store.finishTrip())

        val gpx = assertNotNull(store.exportGpx(id, 400.0))
        assertTrue(gpx.startsWith("<?xml version=\"1.0\""))
        assertTrue(gpx.contains("<gpx version=\"1.1\""))
        assertTrue(gpx.contains("<trkseg>"))
        val fixes = app.vela.core.replay.TripLog.parsePoints(
            assertNotNull(store.exportScrubbedCsv(id, 400.0)).split('\n').filter { it.isNotBlank() },
        ).size
        assertEquals(fixes, Regex("<trkpt ").findAll(gpx).count())
        assertFalse(gpx.contains("Home"), "no trip label in the GPX")
        assertFalse(gpx.contains("<time>"), "no absolute time in the GPX")
    }

    @Test
    fun diagnosticsExportHoldsNoPlace() {
        VelaDiag.reset()
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        val points = path(6)
        val id = assertNotNull(store.startTrip("Secret Place", points.last(), 11L))
        record(store, points)
        assertNotNull(store.finishTrip())
        assertEquals(1, store.list().size)
        VelaDiag.navStarted()
        VelaDiag.warn("nav: reroute FAILED (streak 2)")

        val diagnostics = DiagnosticsStore(
            files = files,
            calibration = null,
            settings = null,
            trips = store,
            offline = { null },
            appVersion = "1.2.3 (45)",
            frameworkVersion = "0.1.0",
        )
        val text = diagnostics.exportText()
        assertTrue(text.contains("app 1.2.3 (45)"))
        assertTrue(text.contains("calibration "))
        assertTrue(text.contains("nav sessions 1"))
        assertTrue(text.contains("recorded trips 1"))
        assertTrue(text.contains("reroute FAILED"))
        assertFalse(text.contains("Secret Place"))
        assertFalse(text.contains(points.last().lat.toString()))
        assertEquals(text, diagnostics.exportText(), "the export is deterministic")
    }

    @Test
    fun stopsAreClustersOfStandstill() {
        val files = TestTripFiles()
        val store = TripsStore(files, TestPrefs(), TestClock())
        val points = path(40)
        val id = assertNotNull(store.startTrip("Stops", points.last(), 1_000_000L))
        points.forEachIndexed { i, p ->
            val speed = if (i in 10..34) 0.0 else 12.0
            store.recordFix(p.lat, p.lng, 1_000_000L + i * 1_000L, 0.0, speed, false, 5.0, "ios", 0)
        }
        assertNotNull(store.finishTrip())
        val detail = assertNotNull(store.detail(id))
        assertEquals(1, detail.stops.size)
        assertEquals(25_000L, detail.stops.single().endMs - detail.stops.single().startMs)
    }
}

/** A [PlatformFiles] with real folder listing, unlike the in-memory MapSession fake. */
private class TestTripFiles : PlatformFiles {
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
            .filter { it.startsWith("$path/") && !it.substringAfter("$path/").contains('/') }
            .map { p -> FileEntry(p.substringAfterLast('/'), p, false, entries[p]!!.size.toLong(), 0L) }
    }
    override fun mkdirs(path: String) = true
    override fun readBytes(path: String) = entries[path] ?: throw IllegalStateException("missing $path")
    override fun readText(path: String) = readBytes(path).decodeToString()
    override fun writeBytes(path: String, bytes: ByteArray) { entries[path] = bytes }
    override fun writeText(path: String, text: String) { entries[path] = text.encodeToByteArray() }
    override fun writeTextAtomic(path: String, text: String) { entries[path] = text.encodeToByteArray() }
    override fun rename(from: String, to: String): Boolean {
        val data = entries.remove(from) ?: return false
        entries[to] = data
        return true
    }
    override fun delete(path: String) = entries.remove(path) != null
    override fun deleteRecursively(path: String): Boolean {
        entries.keys.filter { it == path || it.startsWith("$path/") }.forEach { entries.remove(it) }
        return true
    }
    fun snapshot(): Map<String, ByteArray> = entries.toMap()
}

private class TestPrefs : KeyValueStore {
    private val values = HashMap<String, Any>()
    override fun contains(key: String) = values.containsKey(key)
    override fun getString(key: String, default: String?) = values[key] as? String ?: default
    override fun getLong(key: String, default: Long) = values[key] as? Long ?: default
    override fun getInt(key: String, default: Int) = values[key] as? Int ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as? Boolean ?: default
    override fun getFloat(key: String, default: Float) = values[key] as? Float ?: default
    override fun keys() = values.keys.toSet()
    override fun edit(): KeyValueEditor = object : KeyValueEditor {
        private val pending = LinkedHashMap<String, Any?>()
        override fun putString(key: String, value: String?): KeyValueEditor = apply { pending[key] = value }
        override fun putLong(key: String, value: Long): KeyValueEditor = apply { pending[key] = value }
        override fun putInt(key: String, value: Int): KeyValueEditor = apply { pending[key] = value }
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = apply { pending[key] = value }
        override fun putFloat(key: String, value: Float): KeyValueEditor = apply { pending[key] = value }
        override fun remove(key: String): KeyValueEditor = apply { pending[key] = null }
        override fun clear(): KeyValueEditor = apply { pending.clear() }
        override fun apply() { pending.forEach { (k, v) -> if (v == null) values.remove(k) else values[k] = v!! } }
        override fun commit(): Boolean { apply(); return true }
    }
}

private class TestClock : Clock {
    override fun nowMillis(): Long = 1_000_500L
    override fun elapsedRealtimeMillis(): Long = 500L
    override fun monotonicNanos(): Long = 500_000_000L
}
