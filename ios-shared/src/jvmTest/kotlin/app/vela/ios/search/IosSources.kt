package app.vela.ios.search

import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.google.GoogleMapsSource
import app.vela.core.platform.JsEngine
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.SignatureVerifier
import app.vela.core.platform.VelaHttp
import app.vela.ios.testGraph

/** The iOS Google source over [http] and the compiled calibration, for tests. */
object IosSources {
    fun over(http: VelaHttp, locale: PlatformLocale = FakeLocale("en-US")): GoogleMapsSource {
        val core = testGraph(http, locale = locale)
        val store = CalibrationStore(core, object : SignatureVerifier {
            override fun verify(content: ByteArray, signatureBase64: String, publicKeyBase64: String) = false
        })
        val js = object : JsEngine {
            override fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String? = null
        }
        return IosGoogle.source(core, store, JsTransforms(store, js), IosGoogle.identity(locale))
    }
}
