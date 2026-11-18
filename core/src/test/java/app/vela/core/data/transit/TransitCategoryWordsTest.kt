package app.vela.core.data.transit

import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertTrue
import org.junit.Test

class TransitCategoryWordsTest {

    // Guards the SHIPPED calibration word list: v0.4.670 installs join transitCategoryWords into
    // one regex with no exclusion support, so the guarded "station"-family tokens pushed in v17
    // must reject fuel/EV/emergency categories while keeping real transit matching. Reads the
    // real calibration.json so an edit that breaks the pattern fails CI, not the fleet.
    @Test
    fun `calibration transit words reject fuel stations`() {
        val raw = java.io.File("../calibration.json").takeIf { it.exists() }
            ?: java.io.File("calibration.json")
        val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true }
        val root = json.parseToJsonElement(raw.readText()).jsonObject
        val words = root["transitCategoryWords"]!!.jsonArray.map { it.jsonPrimitive.content }
        val gate = Regex(words.joinToString("|"), RegexOption.IGNORE_CASE)
        // must NOT match (the doubled-board report: a fuel stop next to a bus stop)
        for (bad in listOf(
            "Gas station", "Fuel station", "Filling station", "Service station", "Charging station",
            "Fire station", "Police station", "Radio station", "Television station",
            "Tankstation", "Bensinstation", "Stazione di servizio", "Estación de servicio",
            "Заправочная станция", "תחנת דלק", "Station-service",
        )) assertTrue("should reject: $bad", !gate.containsMatchIn(bad))
        // must still match
        for (good in listOf(
            "Bus stop", "Bus station", "Train station", "Transit station", "Subway station",
            "Light rail station", "Treinstation", "Tågstation", "Gare", "Bahnhof",
            "Stazione ferroviaria", "Estación de tren", "Станция метро", "תחנת אוטובוס",
        )) assertTrue("should match: $good", gate.containsMatchIn(good))
    }
}
