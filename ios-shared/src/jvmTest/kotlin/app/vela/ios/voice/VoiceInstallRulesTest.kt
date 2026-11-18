package app.vela.ios.voice

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VoiceInstallRulesTest {
    @Test fun installedVoiceOffersUseAndRemoveButNoDownload() {
        val row = VoiceInstallRules.row(
            installed = true, inUse = false, downloadingId = null,
            id = "fr_FR-siwis-medium", installing = false, progress = 0.0)
        assertTrue(row.installed)
        assertTrue(row.canUse)
        assertTrue(row.canRemove)
        assertFalse(row.canDownload)
        assertFalse(row.downloading)
    }

    @Test fun inUseVoiceOffersRemoveOnly() {
        val row = VoiceInstallRules.row(
            installed = true, inUse = true, downloadingId = null,
            id = "en_US-hfc_female-medium", installing = false, progress = 0.0)
        assertFalse(row.canUse)
        assertTrue(row.canRemove)
    }

    @Test fun missingVoiceDownloadsOnlyWhenNothingElseIsInFlight() {
        val free = VoiceInstallRules.row(
            installed = false, inUse = false, downloadingId = null,
            id = "de_DE-thorsten-medium", installing = false, progress = 0.0)
        assertTrue(free.canDownload)
        assertFalse(free.canRemove)

        val busy = VoiceInstallRules.row(
            installed = false, inUse = false, downloadingId = "fr_FR-siwis-medium",
            id = "de_DE-thorsten-medium", installing = false, progress = 0.0)
        assertFalse(busy.canDownload)
    }

    @Test fun theDownloadingRowShowsProgressAndCannotBeRemoved() {
        val row = VoiceInstallRules.row(
            installed = true, inUse = false, downloadingId = "fr_FR-siwis-medium",
            id = "fr_FR-siwis-medium", installing = false, progress = 0.426)
        assertTrue(row.downloading)
        assertFalse(row.installing)
        assertEquals(42, row.progressPercent)
        assertFalse(row.canRemove)
        assertFalse(row.canDownload)
    }

    @Test fun installingIsTheLastPhaseAndClampsProgress() {
        val row = VoiceInstallRules.row(
            installed = false, inUse = false, downloadingId = "fr_FR-siwis-medium",
            id = "fr_FR-siwis-medium", installing = true, progress = 1.7)
        assertTrue(row.installing)
        assertEquals(100, row.progressPercent)
    }

    @Test fun aSecondDownloadCannotStart() {
        assertFalse(VoiceInstallRules.canStartDownload(installed = false, downloadingId = "x"))
        assertFalse(VoiceInstallRules.canStartDownload(installed = true, downloadingId = null))
        assertTrue(VoiceInstallRules.canStartDownload(installed = false, downloadingId = null))
    }

    @Test fun removingTheSelectedVoiceClearsThePick() {
        assertNull(VoiceInstallRules.selectionAfterRemove("a", "a"))
        assertEquals("a", VoiceInstallRules.selectionAfterRemove("b", "a"))
        assertEquals("de_DE-thorsten-medium", VoiceInstallRules.selectionAfterInstall("de_DE-thorsten-medium"))
    }
}
