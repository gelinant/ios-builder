package app.vela.ios.voice

import app.vela.core.voice.AsrCatalog
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** VO-2: the phrases a dictation turns into a map action, and the audio-session timeline. */
class VoiceDictationTest {

    private fun plan(heard: String, lang: String = "en") = VoicePlanner.plan(heard, lang)

    @Test fun `plain place stays a search with the spoken filler removed`() {
        assertEquals(
            VoiceRequest(VoiceAction.SEARCH, "coffee", query = "coffee"),
            plan("coffee"),
        )
        assertEquals(
            VoiceRequest(VoiceAction.SEARCH, "where is the nearest gas station", query = "gas station"),
            plan("where is the nearest gas station?", "en"),
        )
        assertEquals(
            VoiceRequest(VoiceAction.SEARCH, "trouve-moi une pharmacie", query = "pharmacie"),
            plan("trouve-moi une pharmacie", "fr"),
        )
    }

    @Test fun `navigate intent keeps its destination`() {
        assertEquals(
            VoiceRequest(VoiceAction.NAVIGATE, "Navigate to the Ferry Building", query = "the ferry building"),
            plan("Navigate to the Ferry Building."),
        )
        // Dictation mishears the verb; the fuzzy pass still reads it.
        assertEquals(
            VoiceAction.NAVIGATE, plan("navigat to the train station")?.action,
        )
    }

    @Test fun `home work route and eta become actions, not queries`() {
        assertEquals(VoiceAction.HOME, plan("take me home")?.action)
        assertEquals(VoiceAction.WORK, plan("get me to work")?.action)
        val route = plan("from davis to san francisco")
        assertEquals(VoiceAction.ROUTE, route?.action)
        assertEquals("davis", route?.from)
        assertEquals("san francisco", route?.to)
        assertEquals(VoiceAction.ETA, plan("what's my ETA")?.action)
    }

    @Test fun `a business named like a command is still a search`() {
        assertEquals(
            VoiceRequest(VoiceAction.SEARCH, "home depot", query = "home depot"),
            plan("home depot"),
        )
    }

    @Test fun `blank or punctuation-only input plans nothing`() {
        assertNull(plan(""))
        assertNull(plan("  ...  "))
        assertEquals("In a quarter mile, turn right", VoicePlanner.clean("  In a quarter mile, turn right.  "))
    }

    @Test fun `audio session ducks once and restores once`() {
        val machine = VoiceAudioMachine()
        assertEquals(listOf(VoiceAudioStep.Duck), machine.started(navSpeaking = false))
        assertEquals(VoiceAudioMachine.Phase.LISTENING, machine.phase)
        assertEquals(emptyList(), machine.started(navSpeaking = false))
        assertEquals(listOf(VoiceAudioStep.Restore), machine.ended())
        assertEquals(VoiceAudioMachine.Phase.CLOSED, machine.phase)
        assertEquals(emptyList(), machine.ended())
    }

    @Test fun `a talking prompt is interrupted before the mic opens`() {
        val steps = VoiceAudioMachine().started(navSpeaking = true)
        assertEquals(listOf(VoiceAudioStep.InterruptGuidance, VoiceAudioStep.Duck), steps)
    }

    @Test fun `guidance asked while listening is held, then spoken after the restore`() {
        val machine = VoiceAudioMachine()
        machine.started(navSpeaking = false)
        assertEquals(
            listOf(VoiceAudioStep.DeferGuidance("In 500 feet, turn right")),
            machine.guidanceRequested("In 500 feet, turn right"),
        )
        machine.guidanceRequested("Turn left")
        assertEquals("Turn left", machine.deferredGuidance)
        assertEquals(listOf(VoiceAudioStep.Restore, VoiceAudioStep.SpeakDeferred), machine.ended())
        assertNull(machine.deferredGuidance)
        // Outside a capture the caller speaks at once; nothing is held.
        assertEquals(emptyList(), machine.guidanceRequested("Recalculating"))
    }

    @Test fun `cancel restores the session exactly like a normal end`() {
        val machine = VoiceAudioMachine()
        machine.started(navSpeaking = true)
        assertEquals(listOf(VoiceAudioStep.Restore), machine.ended())
        assertNull(machine.deferredGuidance)
    }

    @Test fun `the selected engine wins, and a language it cannot speak falls back to whisper`() {
        val sense = AsrCatalog.SENSE_VOICE.id
        val tiny = AsrCatalog.WHISPER_TINY.id
        assertEquals(sense, AsrSelection.forRecognition(listOf(sense), sense, "en"))
        assertEquals(tiny, AsrSelection.forRecognition(listOf(sense, tiny), sense, "he"))
        assertEquals(sense, AsrSelection.forRecognition(listOf(sense), sense, "he"))
        assertNull(AsrSelection.forRecognition(emptyList(), sense, "en"))
        assertEquals(tiny, AsrSelection.activeId(listOf(tiny, "moonshine"), "gone"))
        assertEquals(tiny, IosAsrCatalog.defaultId("en"))
        assertEquals(tiny, IosAsrCatalog.ids().first())
    }

    @Test fun `the catalog keeps the Android ids, urls and model files`() {
        assertEquals(5, AsrCatalog.entries.size)
        assertTrue(AsrCatalog.entries.all { it.url.endsWith("vela-asr-${it.id}.tar.gz") })
        assertTrue(AsrCatalog.entries.all { it.url.startsWith("https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/") })
        assertTrue(AsrCatalog.entries.all { AsrCatalog.VAD in it.files })
        assertEquals(AsrCatalog.WHISPER_TINY, AsrCatalog.defaultFor("en"))
        assertEquals(AsrCatalog.WHISPER_BASE, AsrCatalog.defaultFor("fr"))
        assertEquals("tiny", AsrCatalog.WHISPER_TINY.whisperPrefix)
        assertNull(AsrCatalog.SENSE_VOICE.whisperPrefix)
    }
}
