package app.vela.core.platform

import app.vela.core.net.AgedSession
import app.vela.core.net.GoogleUsage
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit

/**
 * [VelaHttp] over an OkHttp client, normally the shared one from `CoreModule`, so a request passes
 * its interceptors (`NetHealth`, `GoogleTransport.hook` and through it Cronet) and its cookie jar.
 * The call is enqueued on the client's dispatcher.
 *
 * [RequestTags.usageKind] becomes the `GoogleUsage.Kind` tag and [RequestTags.agedSession] the
 * `AgedSession` tag. [HttpRequest.timeoutMillis] sets the call's own timeout, which the Cronet
 * transport reads as its deadline too.
 */
class OkHttpVelaHttp(private val client: OkHttpClient) : VelaHttp {

    override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
        val call = try {
            client.newCall(toOkHttp(request)).also {
                if (request.timeoutMillis > 0) it.timeout().timeout(request.timeoutMillis, TimeUnit.MILLISECONDS)
            }
        } catch (e: Exception) {
            callback(null, e)
            return Cancellable { }
        }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) = callback(null, e)

            override fun onResponse(call: Call, response: Response) {
                val out = try {
                    response.use { fromOkHttp(it) }
                } catch (e: Exception) {
                    callback(null, e)
                    return
                }
                callback(out, null)
            }
        })
        return Cancellable { call.cancel() }
    }

    companion object {
        fun toOkHttp(request: HttpRequest): Request {
            val body = request.body?.toRequestBody(request.contentType?.toMediaTypeOrNull())
                ?: if (request.method == "POST" || request.method == "PUT" || request.method == "PATCH") {
                    ByteArray(0).toRequestBody(request.contentType?.toMediaTypeOrNull())
                } else {
                    null
                }
            return Request.Builder()
                .url(request.url)
                .apply { request.headers.forEach { addHeader(it.name, it.value) } }
                .method(request.method, body)
                .apply {
                    request.tags.usageKind?.let { tag(GoogleUsage.Kind::class.java, GoogleUsage.Kind(it)) }
                    if (request.tags.agedSession) tag(AgedSession::class.java, AgedSession)
                }
                .build()
        }

        fun fromOkHttp(response: Response): HttpResponse = HttpResponse(
            code = response.code,
            headers = (0 until response.headers.size).map { HttpHeader(response.headers.name(it), response.headers.value(it)) },
            body = response.body.bytes(),
            finalUrl = response.request.url.toString(),
        )
    }
}
