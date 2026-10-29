package app.vela.core.data

import app.vela.core.platform.OkHttpVelaHttp
import app.vela.core.platform.VelaHttp
import okhttp3.CookieJar
import okhttp3.OkHttpClient
import kotlin.concurrent.Volatile
import kotlin.time.Duration.Companion.seconds

/**
 * The Android clients of the open-data fetchers in `:core-common` (SPEC 2.5, HTTP requests). Each is
 * an [OkHttpVelaHttp] over a client derived from the shared one with `newBuilder`, so it keeps the
 * shared interceptors, pool and dispatcher. A derived one is built once, from the first base client,
 * as the fetchers did before they moved.
 */
object OpenServicesHttp {
    @Volatile private var overpassHttp: VelaHttp? = null
    @Volatile private var paintedHttp: VelaHttp? = null
    @Volatile private var noRedirectHttp: VelaHttp? = null
    @Volatile private var ndwHttp: VelaHttp? = null

    /** [base] as is: Photon, `OverpassTrafficSignals`, `OverpassPois`, `PaintedRoads.fetchFrom`. */
    fun plain(base: OkHttpClient): VelaHttp = OkHttpVelaHttp(base)

    /** `OverpassAlprCameras` and `OverpassSpeedCameras`: 15 s call, 8 s connect, 15 s read per mirror. */
    fun overpass(base: OkHttpClient): VelaHttp = overpassHttp ?: OkHttpVelaHttp(
        base.newBuilder()
            .callTimeout(15.seconds)
            .connectTimeout(8.seconds)
            .readTimeout(15.seconds)
            .build(),
    ).also { overpassHttp = it }

    /** `PaintedRoads.fetch`: 40 s call and read per mirror. */
    fun paintedRoads(base: OkHttpClient): VelaHttp = paintedHttp ?: OkHttpVelaHttp(
        base.newBuilder().callTimeout(40.seconds).readTimeout(40.seconds).build(),
    ).also { paintedHttp = it }

    /** `NdwBridgeOpenings.fetch`: 20 s call, 8 s connect. */
    fun ndw(base: OkHttpClient): VelaHttp = ndwHttp ?: OkHttpVelaHttp(
        base.newBuilder().callTimeout(20.seconds).connectTimeout(8.seconds).build(),
    ).also { ndwHttp = it }

    /** `ShortLinks.resolve`: no redirect is followed and no cookie is sent or kept. */
    fun noRedirects(base: OkHttpClient): VelaHttp = noRedirectHttp ?: OkHttpVelaHttp(
        base.newBuilder()
            .followRedirects(false).followSslRedirects(false)
            .cookieJar(CookieJar.NO_COOKIES)
            .build(),
    ).also { noRedirectHttp = it }
}
