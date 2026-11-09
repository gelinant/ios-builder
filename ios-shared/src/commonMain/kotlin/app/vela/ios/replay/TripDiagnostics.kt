package app.vela.ios.replay

import app.vela.core.config.Calibration
import app.vela.core.data.NoGoogle
import app.vela.core.net.GoogleUsage
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.joinPath
import app.vela.ios.config.IosCalibration
import app.vela.ios.offline.OfflineState
import app.vela.ios.settings.SettingsStore
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized

/** One labeled count on the diagnostics screen. */
data class DiagCount(val label: String, val count: Int)

/** One labeled switch or engine value on the diagnostics screen. */
data class DiagFlag(val name: String, val value: String)

/**
 * The diagnostics snapshot: versions, engine flags, counts and the last warnings. It holds no
 * coordinate, typed text or place name, which is why it can be exported as text.
 */
data class DiagnosticsSnapshot(
    val appVersion: String,
    val frameworkVersion: String,
    val calibrationVersion: Int,
    val flags: List<DiagFlag>,
    val requestsTotal: Int,
    val requestsToday: Int,
    val requestKinds: List<DiagCount>,
    val offlineRegions: Int,
    val offlinePieces: Int,
    val navSessions: Int,
    val savedTrips: Int,
)

/**
 * The process-wide diagnostics counters. Warnings are short technical lines fed by navigation and
 * recording failures; callers must never pass a coordinate, an address, typed text or a place name.
 */
object VelaDiag {
    private const val MAX_WARNINGS = 10
    private val lock = SynchronizedObject()
    private val warnings = ArrayDeque<String>()
    private var sessions = 0

    fun navStarted() = synchronized(lock) {
        sessions++
    }

    fun warn(text: String) = synchronized(lock) {
        val line = text.replace("\n", " ").replace("\r", "").trim().take(200)
        if (line.isEmpty()) return
        warnings.addLast(line)
        while (warnings.size > MAX_WARNINGS) warnings.removeFirst()
    }

    fun navSessionCount(): Int = synchronized(lock) { sessions }

    fun lastWarnings(): List<String> = synchronized(lock) { warnings.toList() }

    /** Tests only: a snapshot must not inherit another test's session count or warnings. */
    fun reset() = synchronized(lock) {
        sessions = 0
        warnings.clear()
    }
}

/**
 * Builds the diagnostics screen's data and its text export. The numbers come from the same stores
 * the app uses; the export is plain text with no coordinate, search query or place name.
 */
class DiagnosticsStore(
    private val files: PlatformFiles,
    private val calibration: IosCalibration?,
    private val settings: SettingsStore?,
    private val trips: TripsStore,
    private val offline: () -> OfflineState?,
    private val appVersion: String,
    private val frameworkVersion: String,
) {
    fun snapshot(): DiagnosticsSnapshot {
        val cal = runCatching { calibration?.current() ?: Calibration.DEFAULT }.getOrDefault(Calibration.DEFAULT)
        val settingsState = settings?.state?.value
        val usage = GoogleUsage.snapshot()
        val kinds = HashMap<String, Int>()
        for (day in usage.values) for ((kind, count) in day) kinds[kind] = (kinds[kind] ?: 0) + count
        val today = usage.entries.firstOrNull()?.value.orEmpty().values.sum()
        val total = kinds.values.sum()
        val offlineState = offline()
        val installed = offlineState?.regions?.count { it.installed } ?: 0
        val pieces = countPieces()
        val flags = buildList {
            add(DiagFlag("trip recording", if (trips.recordingEnabled) "on" else "off"))
            add(DiagFlag("NoGoogle", if (NoGoogle.enabled) "on" else "off"))
            add(DiagFlag("units", settingsState?.units ?: "system"))
            add(DiagFlag("clock", settingsState?.clockMode ?: "system"))
            add(DiagFlag("language", settingsState?.languageTag?.ifBlank { "system" } ?: "system"))
            add(DiagFlag("calibration refreshed", if (calibration?.refreshed?.value == true) "yes" else "no"))
        }
        return DiagnosticsSnapshot(
            appVersion = appVersion,
            frameworkVersion = frameworkVersion,
            calibrationVersion = cal.version,
            flags = flags,
            requestsTotal = total,
            requestsToday = today,
            requestKinds = kinds.entries.sortedBy { it.key }.map { DiagCount(it.key, it.value) },
            offlineRegions = installed,
            offlinePieces = pieces,
            navSessions = VelaDiag.navSessionCount(),
            savedTrips = trips.list().size,
        )
    }

    /** The export text: the same rows the screen shows, one per line. */
    fun exportText(): String {
        val s = snapshot()
        return buildString {
            appendLine("Vela diagnostics")
            appendLine("app ${s.appVersion}")
            appendLine("framework ${s.frameworkVersion}")
            appendLine("calibration ${s.calibrationVersion}")
            appendLine()
            appendLine("flags")
            for (f in s.flags) appendLine("  ${f.name}: ${f.value}")
            appendLine()
            appendLine("requests ${s.requestsTotal} total, ${s.requestsToday} today")
            for (k in s.requestKinds) appendLine("  ${k.label} ${k.count}")
            appendLine("offline ${s.offlineRegions} regions, ${s.offlinePieces} pieces")
            appendLine("nav sessions ${s.navSessions}")
            appendLine("recorded trips ${s.savedTrips}")
            appendLine()
            val warnings = VelaDiag.lastWarnings()
            if (warnings.isEmpty()) {
                appendLine("warnings none")
            } else {
                appendLine("warnings")
                for (w in warnings) appendLine("  $w")
            }
        }
    }

    /** Files under the offline root, grouped the way the offline screen counts them as pieces. */
    private fun countPieces(): Int {
        val root = joinPath(files.noBackupDir, "offline")
        var count = 0
        for (folder in listOf("basemap", "places", "poipacks", "regions")) {
            count += files.list(joinPath(root, folder)).orEmpty().count { !it.isDirectory }
        }
        return count
    }
}
