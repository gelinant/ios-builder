package app.vela.core.platform

import android.content.res.Resources
import android.os.LocaleList
import java.util.Locale

/** [PlatformLocale] over `Locale.getDefault()`, `LocaleList.getDefault()` and
 *  `Resources.getSystem()`. */
object AndroidPlatformLocale : PlatformLocale {
    override fun defaultTag(): String = Locale.getDefault().toLanguageTag()
    override fun defaultLanguage(): String = Locale.getDefault().language
    override fun preferredTags(): List<String> = LocaleList.getDefault().tags()
    override fun systemTags(): List<String> = Resources.getSystem().configuration.locales.tags()

    private fun LocaleList.tags(): List<String> = (0 until size()).map { get(it).toLanguageTag() }
}
