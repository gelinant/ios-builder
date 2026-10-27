package app.vela.core.platform

/** The Unicode normalization forms (UAX #15). */
enum class NormalForm { NFC, NFD, NFKC, NFKD }

/**
 * Unicode normalization (SPEC "Platform seams"). Android: `java.text.Normalizer`; iOS:
 * `NSString` precomposed and decomposed mappings.
 *
 * Removing the marks after a decomposition stays with each caller, with its own `Regex`:
 * `OfflineRank.fold` folds Latin letters only, and folding every script breaks kana, Hangul and
 * Indic vowel signs (CLAUDE.md, Languages).
 */
interface TextNormalizer {
    fun normalize(text: String, form: NormalForm): String
}
