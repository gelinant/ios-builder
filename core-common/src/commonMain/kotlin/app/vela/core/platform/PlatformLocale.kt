package app.vela.core.platform

/**
 * The languages the device and the app run in (SPEC "Platform seams"). Every call reads the
 * current value: the in-app language can change while the process runs.
 */
interface PlatformLocale {
    /** BCP 47 tag of the process default locale (`Locale.getDefault().toLanguageTag()`). On
     *  Android this is the in-app language once `AppLocale.wrap` has run. */
    fun defaultTag(): String

    /** Language code of the process default locale (`Locale.getDefault().language`). Android
     *  keeps the legacy codes `iw`, `in` and `ji` for Hebrew, Indonesian and Yiddish; callers
     *  that key tables on the code rely on them. */
    fun defaultLanguage(): String

    /** The process's preferred languages as BCP 47 tags, first is preferred
     *  (`LocaleList.getDefault()`), the list the WebViews send. */
    fun preferredTags(): List<String>

    /** The device's own languages as BCP 47 tags, unaffected by the in-app language
     *  (`Resources.getSystem().configuration.locales`). */
    fun systemTags(): List<String>
}
