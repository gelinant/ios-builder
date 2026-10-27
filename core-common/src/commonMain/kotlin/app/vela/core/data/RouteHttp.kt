package app.vela.core.data

import app.vela.core.platform.VelaHttp

/**
 * The HTTP client of the open router's fetches ([RouteGeometry], SPEC 2.5). A bounded fetch
 * ([RouteBudget]) gives each attempt only its share of the deadline, and on Android that share
 * caps the connect, read and write timeouts as well as the call: [bounded] is the client for one
 * such attempt. The request also carries the share as its own deadline
 * ([app.vela.core.platform.HttpRequest.timeoutMillis]), so a client without those settings can
 * answer [bounded] with [http].
 */
interface RouteHttp {
    /** The client of an unbounded fetch, with its own timeouts. */
    val http: VelaHttp

    /** The client of one attempt with every timeout at [ms]. */
    fun bounded(ms: Long): VelaHttp

    /** What a failed attempt is called in the failure report: "timeout" for a deadline, else
     *  the error's class name. */
    fun failureName(error: Throwable): String

    companion object {
        /** [http] for every attempt; [isTimeout] tells a deadline from another failure. */
        fun of(http: VelaHttp, isTimeout: (Throwable) -> Boolean = { false }): RouteHttp = object : RouteHttp {
            override val http: VelaHttp = http
            override fun bounded(ms: Long): VelaHttp = http
            override fun failureName(error: Throwable): String =
                if (isTimeout(error)) "timeout" else error::class.simpleName.orEmpty()
        }
    }
}
