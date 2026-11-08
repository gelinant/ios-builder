package app.vela.core.web

import app.vela.core.data.ReviewWords
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * The reviews scrape script moved from `app.vela.web.WebReviewsFetcher` without a byte changing.
 * `web/reviews-before.js` is the script the Android source built before the move (request id
 * `@@ID@@`, cap 50, the compiled words and selectors), evaluated from that source by
 * `tools/ios-spike-web/gen_js.py`.
 */
class ReviewScriptsTest {
    private val before = javaClass.getResourceAsStream("/web/reviews-before.js")!!.readBytes().decodeToString()

    private fun script(id: String = "@@ID@@", cap: Int = 50, selectors: Map<String, String> = emptyMap()) =
        ReviewScripts.reviews(id, cap, ReviewWords.REVIEW_PATTERN, ReviewWords.MORE_PATTERN, selectors)

    @Test fun theMovedScriptIsTheOneAndroidBuiltBefore() {
        assertEquals(before, script())
    }

    @Test fun theCapAndTheIdAreTheOnlyParts() {
        assertEquals(before.replace("var CAP=50;", "var CAP=10;").replace("\"@@ID@@\"", "\"7\""), script(id = "7", cap = 10))
    }

    @Test fun aCalibratedSelectorReplacesItsDefault() {
        val s = script(selectors = mapOf("card" to ".newCard"))
        assertTrue("\"card\":\".newCard\"" in s)
        assertTrue("\"id\":\"[data-review-id]\"" in s)
    }

    @Test fun theBridgeKeepsItsReadableNameForTheAppsToSwap() {
        assertTrue("VelaBridge.onResult(ID" in script())
        assertTrue("function velaNoName(t)" in script())
    }

    @Test fun theTranslationFlagIsAnAppendAndTheDefaultBytesStay() {
        val flagged = ReviewScripts.reviews(
            "@@ID@@", 50, ReviewWords.REVIEW_PATTERN, ReviewWords.MORE_PATTERN, translations = true)
        assertTrue("function velaTranslated(c)" in flagged)
        assertTrue("tr:velaTranslated(c)" in flagged)
        assertEquals(before, script())
    }
}
