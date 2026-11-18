package app.vela.core.voice

/**
 * The on-device speech-to-text engines the app can download for voice search. The list mirrors
 * Android's `AsrEngine` (`:app`, kept there because it reads Android preferences) and both point at
 * the same `asr-models` release of the Vela repository: same ids, same archives, same file layout.
 *
 * The archives contain a sherpa-onnx model plus Silero VAD. Nothing leaves the phone. This object is
 * pure metadata, so iOS reads it from `:core-common` while Android keeps its Android-specific
 * install check and preference.
 */
enum class AsrCatalog(
    val id: String,
    /** Proper-noun engine name shown in a picker. */
    val displayName: String,
    /** sherpa-onnx `modelType` string the recognizer passes through. */
    val modelType: String,
    val sizeMb: Int,
    /** Asset on the `asr-models` release. */
    val url: String,
    /** Archive size and SHA-256, checked before extraction. */
    val bytes: Long,
    val sha256: String,
    /** Every file that must be present and non-empty for the engine to count as installed. */
    val files: List<String>,
) {
    WHISPER_TINY(
        id = "whisper-tiny",
        displayName = "Whisper tiny",
        modelType = "whisper",
        sizeMb = 58,
        url = "https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/vela-asr-whisper-tiny.tar.gz",
        bytes = 61_255_404,
        sha256 = "ae93a93e04b6b4d86753f123e5539d216fe5a52dcf441d0e7fc97d05b3568d2e",
        files = listOf("tiny-encoder.int8.onnx", "tiny-decoder.int8.onnx", "tiny-tokens.txt", "silero_vad.onnx"),
    ),
    WHISPER_BASE(
        id = "whisper-base",
        displayName = "Whisper base",
        modelType = "whisper",
        sizeMb = 91,
        url = "https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/vela-asr-whisper-base.tar.gz",
        bytes = 94_973_801,
        sha256 = "f7bdea62be629b2d0484db9631575e505a78217a7ec479f302b1577d7f7195e3",
        files = listOf("base-encoder.int8.onnx", "base-decoder.int8.onnx", "base-tokens.txt", "silero_vad.onnx"),
    ),
    WHISPER_SMALL(
        id = "whisper-small",
        displayName = "Whisper small",
        modelType = "whisper",
        sizeMb = 222,
        url = "https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/vela-asr-whisper-small.tar.gz",
        bytes = 233_183_250,
        sha256 = "f62624187aca6b94d1d899e2b856a0f55b8795b9ee23a74d2b04bad3dc244d7e",
        files = listOf("small-encoder.int8.onnx", "small-decoder.int8.onnx", "small-tokens.txt", "silero_vad.onnx"),
    ),
    SENSE_VOICE(
        id = "sensevoice",
        displayName = "SenseVoice",
        modelType = "sense_voice",
        sizeMb = 154,
        url = "https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/vela-asr-sensevoice.tar.gz",
        bytes = 160_816_590,
        sha256 = "162e1805eb5b05d1a4c1efc482f9961916ba47bb6617a85ed9746cf40fa432ff",
        files = listOf("model.int8.onnx", "tokens.txt", "silero_vad.onnx"),
    ),
    MOONSHINE(
        id = "moonshine",
        displayName = "Moonshine",
        modelType = "moonshine",
        sizeMb = 101,
        url = "https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/vela-asr-moonshine.tar.gz",
        bytes = 105_274_655,
        sha256 = "f7d94ea9cb59210da573217f964d4bfb6024fdc494c7f9c5cd989aa3bab78358",
        files = listOf(
            "preprocess.onnx", "encode.int8.onnx", "uncached_decode.int8.onnx",
            "cached_decode.int8.onnx", "tokens.txt", "silero_vad.onnx",
        ),
    ),
    ;

    /** The Whisper files' prefix (`tiny-encoder.int8.onnx`), null for another model. */
    val whisperPrefix: String? get() = if (modelType == "whisper") id.removePrefix("whisper-") else null

    /** Whether this engine can recognize [lang] (an app language code such as `en`, `he`, `ja`). */
    fun supportsLanguage(lang: String): Boolean = when (this) {
        WHISPER_TINY, WHISPER_BASE, WHISPER_SMALL -> true
        SENSE_VOICE -> lang in SENSE_VOICE_LANGS
        MOONSHINE -> lang == "en"
    }

    companion object {
        /** Silero VAD, shipped inside every engine archive so each one is self-contained. */
        const val VAD = "silero_vad.onnx"

        /** The languages SenseVoice recognizes. */
        val SENSE_VOICE_LANGS = setOf("zh", "en", "ja", "ko", "yue")

        fun byId(id: String?): AsrCatalog? = entries.firstOrNull { it.id == id }

        /**
         * The engine offered when nothing is installed: Whisper tiny for English, where it is good
         * and smallest; Whisper base for any other language, where tiny is too weak to use. Never
         * SenseVoice or Moonshine, which are opt-in for the languages they cover.
         */
        fun defaultFor(lang: String): AsrCatalog = if (lang == "en") WHISPER_TINY else WHISPER_BASE
    }
}
