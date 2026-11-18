package app.vela.ios.voice

import app.vela.core.voice.PiperCatalog
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class VoiceSelectionTest {
    private val hfc = "en_US-hfc_female-medium"
    private val siwis = "fr_FR-siwis-medium"

    @Test
    fun `catalog keeps the Android ids and download scheme`() {
        assertEquals(43, PiperCatalog.ALL.size)
        assertEquals("en_US-hfc_female-medium", PiperCatalog.defaultFor("en").id)
        assertEquals("fr_FR-siwis-medium", PiperCatalog.defaultFor("fr").id)
        assertEquals(
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-siwis-medium.tar.bz2",
            PiperCatalog.downloadUrl(siwis),
        )
        assertNotNull(PiperCatalog.byId(hfc))
    }

    @Test
    fun `language comes from a catalog id or a locale tag`() {
        assertEquals("en", IosVoiceSelection.languageOf(hfc))
        assertEquals("fr", IosVoiceSelection.languageOf(siwis))
        assertEquals("pt", IosVoiceSelection.languageOf("pt-BR"))
        assertEquals("zh", IosVoiceSelection.languageOf("zh_Hant"))
    }

    @Test
    fun `complete layout needs model tokens and espeak data`() {
        val full = setOf("$hfc.onnx", "tokens.txt", "espeak-ng-data/en_dict")
        assertTrue(IosVoiceSelection.isComplete(hfc, full))
        assertFalse(IosVoiceSelection.isComplete(hfc, emptySet()))
        assertFalse(IosVoiceSelection.isComplete(hfc, setOf("$hfc.onnx", "tokens.txt")))
        assertFalse(IosVoiceSelection.isComplete(hfc, setOf("$hfc.onnx", "espeak-ng-data/en_dict")))
        // A partial extraction of another voice does not make this id complete.
        assertFalse(IosVoiceSelection.isComplete(hfc, setOf("$siwis.onnx", "tokens.txt", "espeak-ng-data")))
    }

    @Test
    fun `missing model keeps the system voice`() {
        assertNull(IosVoiceSelection.effectiveVoiceId(emptyList(), hfc, "en"))
        assertEquals(IosVoiceSelection.SYSTEM, IosVoiceSelection.engine(emptyList(), hfc, "en"))
        assertEquals("no-voice", IosVoiceSelection.fallbackReason(emptyList(), hfc, "en"))
    }

    @Test
    fun `selected voice wins when installed and matching`() {
        val installed = listOf(hfc, "en_US-lessac-medium", siwis)
        assertEquals(hfc, IosVoiceSelection.effectiveVoiceId(installed, hfc, "en"))
        assertEquals(IosVoiceSelection.NEURAL, IosVoiceSelection.engine(installed, hfc, "en"))
        assertNull(IosVoiceSelection.fallbackReason(installed, hfc, "en"))
    }

    @Test
    fun `wrong language selection falls back to a matching voice`() {
        val installed = listOf(hfc, siwis)
        assertEquals(siwis, IosVoiceSelection.effectiveVoiceId(installed, hfc, "fr"))
        assertNull(IosVoiceSelection.fallbackReason(installed, hfc, "fr"))
    }

    @Test
    fun `selection of another language without a match keeps the system voice`() {
        val installed = listOf(siwis)
        assertEquals(IosVoiceSelection.SYSTEM, IosVoiceSelection.engine(installed, siwis, "en"))
        assertEquals("voice-language", IosVoiceSelection.fallbackReason(installed, siwis, "en"))
        assertEquals("language-missing", IosVoiceSelection.fallbackReason(installed, null, "en"))
    }
}
