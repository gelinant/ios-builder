package app.vela.ios.diag

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CrashReportTest {
    @Test
    fun rotationKeepsTheThreeNewestByTheirStamp() {
        val names = listOf(
            "crash-1000.txt",
            "notes.txt",
            "crash-9.txt",
            "crash-3000.txt",
            "crash-2500.txt",
            "crash-2000.txt",
        )
        assertEquals(listOf("crash-9.txt", "crash-1000.txt"), CrashReport.rotate(names))
    }

    @Test
    fun rotationHasNothingToDeleteBelowTheLimit() {
        val names = listOf("crash-10.txt", "crash-11.txt", "crash-12.txt")
        assertTrue(CrashReport.rotate(names).isEmpty())
    }

    @Test
    fun aBacktraceKeepsItsFramesAndLosesPlaces() {
        val raw = """
            Vela crash report
            reason: uncaught NSException in "Union Square" https://maps.example/place/42
            last fix 37.7749295,-122.4194155
            0   Vela   0x0000000104a2b3c4 -[VelaMapViewController loadTiles] + 88
            1   Vela   0x0000000104a2d110 ${"$"}s4Vela11MapRendererC4drawyyF + 24
            2   UIKit  0x0000000180a1b2c3 -[UIApplication _run] + 100
            at /Users/alice/vela/iosApp/Vela/Map/MapController.swift:120
        """.trimIndent()
        val redacted = CrashReport.redact(raw, redactPlaces = false)
        assertTrue(redacted.contains("-[VelaMapViewController loadTiles] + 88"))
        assertTrue(redacted.contains("${"$"}s4Vela11MapRendererC4drawyyF"))
        assertTrue(redacted.contains("37.77,-122.42"), redacted)
        assertTrue(redacted.contains("https://maps.example/[redacted]"), redacted)
        assertFalse(redacted.contains("/Users/alice"), redacted)
        // The quoted place survives without the opt-in: coordinates are the only rule there.
        assertTrue(redacted.contains("\"Union Square\""))
    }

    @Test
    fun theRedactPlacesSettingAlsoDropsQuotedText() {
        val raw = "reason: \"Coffee Shop\" at 37.7749295,-122.4194155"
        val redacted = CrashReport.redact(raw, redactPlaces = true)
        assertTrue(redacted.contains("\"[redacted]\""), redacted)
        assertTrue(redacted.contains("37.8,-122.4"), redacted)
        assertFalse(redacted.contains("Coffee Shop"), redacted)
    }
}
