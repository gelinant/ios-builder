package app.vela.ios

import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NormalForm
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.TextNormalizer
import app.vela.core.platform.VelaHttp
import app.vela.ios.config.MemoryFiles
import app.vela.ios.search.FakeLocale

/** A [CoreGraph] over [http] and in-memory files, for the tests that build the Google source. */
fun testGraph(http: VelaHttp, files: PlatformFiles = MemoryFiles(), locale: PlatformLocale = FakeLocale("en-US")) = CoreGraph(
    log = object : Log {
        override fun isLoggable(tag: String, level: LogLevel) = false
        override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
    },
    clock = object : Clock {
        override fun nowMillis() = 0L
        override fun elapsedRealtimeMillis() = 0L
        override fun monotonicNanos() = 0L
    },
    keyValues = object : KeyValueStores {
        override fun open(name: String): KeyValueStore = throw UnsupportedOperationException()
    },
    files = files,
    http = http,
    text = object : TextNormalizer {
        override fun normalize(text: String, form: NormalForm) = text
    },
    locale = locale,
)
