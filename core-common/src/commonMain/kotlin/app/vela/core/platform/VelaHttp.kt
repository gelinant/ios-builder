package app.vela.core.platform

import kotlinx.atomicfu.atomic
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** One header line. Names keep the case they were given. */
data class HttpHeader(val name: String, val value: String)

/**
 * What a request carries for the transport and not for the server (SPEC "Platform seams").
 * Android maps each onto the OkHttp request tag the shared client reads today.
 */
data class RequestTags(
    /** The purpose a Google request is counted under (`GoogleUsage.Kind`). Null: the counter
     *  reads it off the URL (`GoogleUsage.kindOf`). */
    val usageKind: String? = null,
    /** Send this Google request with the WebView's aged session (`net/AgedSession`). Set by the
     *  caller after checking the `agedSession` dial. */
    val agedSession: Boolean = false,
    /**
     * Let this request reach a Google host even while "Use Vela without Google" is on. Only a
     * caller that has its own explicit user answer may set it: today the one cookieless hop that
     * asks Google's link shortener where a shared short link points (SET-PRIVACY).
     */
    val allowGoogleWhenOff: Boolean = false,
) {
    companion object {
        val NONE = RequestTags()
    }
}

/**
 * One HTTP request. [headers] go out in list order; a name listed twice is sent twice.
 */
class HttpRequest(
    val url: String,
    val method: String = "GET",
    val headers: List<HttpHeader> = emptyList(),
    /** Null for a request without a body. A POST without one sends an empty body. */
    val body: ByteArray? = null,
    /** The `Content-Type` of [body], sent exactly as given. */
    val contentType: String? = null,
    val tags: RequestTags = RequestTags.NONE,
    /** Deadline for the whole call in milliseconds. 0 keeps the client's own deadline (12 s on
     *  the shared Android client). */
    val timeoutMillis: Long = 0,
)

/** A complete response. Any status code is a response; only a failure to get one is an error. */
class HttpResponse(
    val code: Int,
    /** In the order received. */
    val headers: List<HttpHeader>,
    val body: ByteArray,
    /** The URL that answered, after redirects. */
    val finalUrl: String,
) {
    val isSuccessful: Boolean get() = code in 200..299

    /** The last value of the header [name], compared without case (OkHttp's `header`). */
    fun header(name: String): String? = headers.lastOrNull { it.name.equals(name, ignoreCase = true) }?.value

    /** [body] decoded as UTF-8. */
    fun bodyText(): String = body.decodeToString()
}

/** A started operation that can be stopped. */
fun interface Cancellable {
    /** Stops the operation. Safe to call more than once and after it finished. */
    fun cancel()
}

/**
 * The HTTP client (SPEC "Platform seams"). Android: the shared OkHttp client, so Google requests
 * still pass the request counter and the Cronet transport. iOS: `URLSession`.
 */
interface VelaHttp {
    /**
     * Starts [request] and returns at once. [callback] runs once, on any thread, with a response
     * or with the error that prevented one. After [Cancellable.cancel] it runs at most once more,
     * with an error, or not at all.
     */
    fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable
}

/**
 * [VelaHttp.execute] as a suspend call. Cancelling the coroutine cancels the request. An error from
 * the client is rethrown as is; a callback with neither a response nor an error throws
 * [IllegalStateException]. A second callback is ignored.
 */
suspend fun VelaHttp.call(request: HttpRequest): HttpResponse = suspendCancellableCoroutine { cont ->
    val done = atomic(false)
    val handle = execute(request) { response, error ->
        if (!done.compareAndSet(false, true)) return@execute
        when {
            error != null -> cont.resumeWithException(error)
            response != null -> cont.resume(response)
            else -> cont.resumeWithException(IllegalStateException("VelaHttp callback without a response or an error"))
        }
    }
    cont.invokeOnCancellation { handle.cancel() }
}
