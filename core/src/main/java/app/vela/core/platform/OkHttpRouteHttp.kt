package app.vela.core.platform

import app.vela.core.data.RouteHttp
import okhttp3.OkHttpClient
import java.io.InterruptedIOException
import kotlin.time.Duration.Companion.milliseconds

/**
 * [RouteHttp] over an OkHttp client (normally the shared one). [bounded] derives a client with the
 * call, connect, read and write timeouts all at the attempt's share, as `RouteBudget.bounded` did
 * before the router moved: `newBuilder` shares the connection pool and dispatcher, so this is cheap
 * enough for the few calls a reroute makes. A timeout is OkHttp's `InterruptedIOException`.
 */
class OkHttpRouteHttp(private val base: OkHttpClient) : RouteHttp {
    override val http: VelaHttp = OkHttpVelaHttp(base)

    override fun bounded(ms: Long): VelaHttp {
        val t = ms.coerceAtLeast(1L)
        return OkHttpVelaHttp(
            base.newBuilder()
                .callTimeout(t.milliseconds)
                .connectTimeout(t.milliseconds)
                .readTimeout(t.milliseconds)
                .writeTimeout(t.milliseconds)
                .build(),
        )
    }

    override fun failureName(error: Throwable): String =
        if (error is InterruptedIOException) "timeout" else error.javaClass.simpleName
}
