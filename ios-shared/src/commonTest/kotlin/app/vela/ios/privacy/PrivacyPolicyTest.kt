package app.vela.ios.privacy

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PrivacyPolicyTest {
    private val hour = 3_600_000L
    private val day = 24 * hour

    @Test fun weekIsTheDefaultAndTheLongestPeriod() {
        assertEquals("week", PrivacyPolicy.normalizeRotation(""))
        assertEquals("week", PrivacyPolicy.normalizeRotation("year"))
        assertEquals(7 * day, PrivacyPolicy.rotationPeriodMillis("week"))
        assertEquals(day, PrivacyPolicy.rotationPeriodMillis("day"))
        assertEquals(0L, PrivacyPolicy.rotationPeriodMillis("launch"))
    }

    @Test fun aSessionIsDueAfterItsPeriodOrOnEveryLaunch() {
        val started = 1_000_000L
        assertFalse(PrivacyPolicy.isRotationDue("week", started, started + 7 * day - 1))
        assertTrue(PrivacyPolicy.isRotationDue("week", started, started + 7 * day))
        assertFalse(PrivacyPolicy.isRotationDue("day", started, started + day - 1))
        assertTrue(PrivacyPolicy.isRotationDue("day", started, started + day))
        assertTrue(PrivacyPolicy.isRotationDue("launch", started, started))
        assertFalse(PrivacyPolicy.isRotationDue("week", 0L, started + 30 * day))
    }

    @Test fun googleHostsAreRecognizedWithoutLookalikes() {
        for (host in listOf(
            "www.google.com", "google.com", "play.google.com", "maps.googleapis.com",
            "csi.gstatic.com", "lh3.googleusercontent.com", "www.google.fr",
            "www.google.co.uk", "adservice.google.com", "doubleclick.net",
        )) {
            assertTrue(PrivacyPolicy.isGoogleHost(host), host)
        }
        for (host in listOf("notgoogle.com", "google.com.example.org", "example.com", "", "photon.komoot.io")) {
            assertFalse(PrivacyPolicy.isGoogleHost(host), host)
        }
    }

    @Test fun telemetryRulesCoverTheThreePageCallsOnly() {
        assertEquals(3, PrivacyPolicy.telemetryRuleFilters.size)
        assertTrue(PrivacyPolicy.telemetryRuleFilters.any { it.contains("play\\.google\\.com/log") })
        assertTrue(PrivacyPolicy.telemetryRuleFilters.any { it == "/gen_204" })
        assertTrue(PrivacyPolicy.telemetryRuleFilters.any { it.contains("ogads-pa") })
        val json = PrivacyPolicy.telemetryRulesJson()
        assertTrue(json.startsWith("["))
        assertEquals(3, Regex("\"type\":\"block\"").findAll(json).count())
        assertEquals(3, Regex("\"url-filter\"").findAll(json).count())
        // The main place, photo and search endpoints are not in the list.
        assertFalse(json.contains("/maps/"))
        assertFalse(json.contains("/search"))
    }

    @Test fun diagnosticsDropUrlsCoordinatesAndQuotedText() {
        val line = "open https://www.google.com/maps/place/x?pb=abc at 37.7749,-122.4194 \"Ferry Building\" id 1234567"
        val redacted = PrivacyPolicy.redactDiagnosticLine(line)
        assertFalse(redacted.contains("pb=abc"))
        assertFalse(redacted.contains("37.7749"))
        assertFalse(redacted.contains("-122.4194"))
        assertFalse(redacted.contains("Ferry Building"))
        assertFalse(redacted.contains("1234567"))
        assertTrue(redacted.contains("<coordinates>"))
    }

    @Test fun theReportCarriesVersionsFlagsAndNoSecret() {
        val report = PrivacyPolicy.diagnosticsReport(
            appVersion = "0.1.1", buildNumber = "42", calibrationVersion = 27,
            flags = listOf("no_google=1", "telemetry_blocked=0"),
            logLines = listOf("search \"coffee\" at 37.7749,-122.4194"),
        )
        assertTrue(report.contains("app: 0.1.1 (42)"))
        assertTrue(report.contains("calibration: 27"))
        assertTrue(report.contains("no_google=1"))
        assertFalse(report.contains("coffee"))
        assertFalse(report.contains("37.7749"))
    }
}
