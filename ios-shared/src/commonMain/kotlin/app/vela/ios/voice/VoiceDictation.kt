package app.vela.ios.voice

import app.vela.ios.search.SearchCommandPlan
import app.vela.ios.search.SearchCommands

/**
 * The actions a spoken query can ask for. Strings, not an enum, because Swift switches on them:
 * the ids are the contract with the iOS layer.
 */
object VoiceAction {
    const val SEARCH = "search"
    const val NAVIGATE = "navigate"
    const val HOME = "home"
    const val WORK = "work"
    const val ROUTE = "route"
    const val ETA = "eta"
    const val ALONG = "along"
    const val CALL = "call"
}

/**
 * One recognized phrase turned into an action. [display] is the cleaned phrase for the search
 * field; [query] is what to search for, with the spoken filler removed ("nearest gas station" ->
 * "gas station"); [from] and [to] are the ends of an "A to B" route.
 */
data class VoiceRequest(
    val action: String,
    val display: String,
    val query: String = "",
    val from: String? = null,
    val to: String? = null,
)

/**
 * The bridge between dictation and the map. The recognizer only produces text; the meaning comes
 * from the shared [QueryIntents] parser, the same one Android's voice dialog uses, so iOS cannot
 * grow a second search vocabulary. Anything the parser does not recognize stays a plain search,
 * which is why a business called "Home Depot" still searches instead of driving home.
 */
object VoicePlanner {
    /** Trimmed transcript without the trailing sentence punctuation recognizers like to add. */
    fun clean(heard: String): String =
        heard.trim()
            .trimEnd('.', '!', '?', ',', ';', ':')
            .replace(Regex("\\s+"), " ")
            .trim()

    /** The action for [heard] in language [lang], or null when nothing usable was heard. */
    fun plan(heard: String, lang: String): VoiceRequest? {
        val text = clean(heard)
        if (text.isEmpty()) return null
        val command = SearchCommands.parse(text, lang)
        if (command == null) return VoiceRequest(VoiceAction.SEARCH, text, query = text)
        return planOf(command, text)
    }

    private fun planOf(command: SearchCommandPlan, display: String): VoiceRequest =
        when (command.kind) {
            SearchCommands.HOME -> VoiceRequest(VoiceAction.HOME, display)
            SearchCommands.WORK -> VoiceRequest(VoiceAction.WORK, display)
            SearchCommands.DIRECTIONS ->
                VoiceRequest(VoiceAction.NAVIGATE, display, query = command.query)
            SearchCommands.ALONG -> VoiceRequest(VoiceAction.ALONG, display, query = command.query)
            SearchCommands.CALL -> VoiceRequest(VoiceAction.CALL, display, query = command.query)
            SearchCommands.ROUTE -> VoiceRequest(
                VoiceAction.ROUTE, display, from = command.from, to = command.to)
            SearchCommands.ETA -> VoiceRequest(VoiceAction.ETA, display)
            else -> VoiceRequest(VoiceAction.SEARCH, display, query = command.query)
        }
}

/** One step the platform layer must take on the audio session. */
sealed interface VoiceAudioStep {
    /** A guidance prompt is talking: stop it before recording, rather than mix with it. */
    data object InterruptGuidance : VoiceAudioStep

    /** Lower other apps' audio for the capture (`.duckOthers`). */
    data object Duck : VoiceAudioStep

    /** Guidance asked to speak while the mic is open; the line waits for the capture to end. */
    data class DeferGuidance(val text: String) : VoiceAudioStep

    /** Back to the category captured before the first duck. */
    data object Restore : VoiceAudioStep

    /** Speak the last deferred guidance line, now that the mic is closed. */
    data object SpeakDeferred : VoiceAudioStep
}

/**
 * The audio-session timeline of one dictation attempt, kept pure so Linux can test it.
 *
 * The rules it enforces:
 *  - duck once, on start, never per sample;
 *  - never fight an active guidance prompt: stop it first, and while listening hold guidance
 *    rather than let two engines talk over the microphone;
 *  - restore exactly once, whether the attempt succeeded, failed or was cancelled, because a mic
 *    left open keeps the audio session in `.playAndRecord` and silences navigation afterwards.
 */
class VoiceAudioMachine {
    enum class Phase { IDLE, LISTENING, CLOSED }

    var phase: Phase = Phase.IDLE
        private set

    /** The latest guidance line held while listening, newest wins. */
    var deferredGuidance: String? = null
        private set

    /** Start listening. [navSpeaking] interrupts the prompt in flight instead of mixing with it. */
    fun started(navSpeaking: Boolean): List<VoiceAudioStep> {
        if (phase == Phase.LISTENING) return emptyList()
        phase = Phase.LISTENING
        deferredGuidance = null
        val steps = ArrayList<VoiceAudioStep>(2)
        if (navSpeaking) steps.add(VoiceAudioStep.InterruptGuidance)
        steps.add(VoiceAudioStep.Duck)
        return steps
    }

    /** Guidance wants to speak. Returns [] when it may speak immediately. */
    fun guidanceRequested(text: String): List<VoiceAudioStep> {
        if (phase != Phase.LISTENING || text.isBlank()) return emptyList()
        deferredGuidance = text
        return listOf(VoiceAudioStep.DeferGuidance(text))
    }

    /** The attempt ended for any reason: release the session, then release held guidance. */
    fun ended(): List<VoiceAudioStep> {
        if (phase != Phase.LISTENING) return emptyList()
        phase = Phase.CLOSED
        val held = deferredGuidance
        deferredGuidance = null
        val steps = ArrayList<VoiceAudioStep>(2)
        steps.add(VoiceAudioStep.Restore)
        if (held != null) steps.add(VoiceAudioStep.SpeakDeferred)
        return steps
    }
}
