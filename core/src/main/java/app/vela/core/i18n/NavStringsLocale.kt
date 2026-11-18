package app.vela.core.i18n

import java.util.Locale

/**
 * The `java.util.Locale` side of [NavStrings], which `:core-common` names by plain codes.
 * [javaLocale] is built as the tables used to be (`Locale("he", "IL")`), so on Android its
 * `language` is still the legacy code ("iw", "in", "ji") that a TTS voice's locale reports.
 */
val NavStrings.javaLocale: Locale get() = Locale(language, region)

/** Selects the table for [locale]: its language, country and script, as [NavStringsRegistry.tagOf]. */
fun NavStringsRegistry.setLocale(locale: Locale) = setLanguage(locale.language, locale.country, locale.script)

/** [NavStringsRegistry.tagOf] for a `java.util.Locale`. */
fun NavStringsRegistry.tagOf(locale: Locale): String = tagOf(locale.language, locale.country, locale.script)
