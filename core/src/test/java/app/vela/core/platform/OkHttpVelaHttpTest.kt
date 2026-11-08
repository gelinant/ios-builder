package app.vela.core.platform

import app.vela.core.net.AgedSession
import app.vela.core.net.GoogleTransport
import app.vela.core.net.GoogleUsage
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** The OkHttp-backed [VelaHttp] against interceptors that answer locally: no network. */
class OkHttpVelaHttpTest {
    private class Seen(val request: Request, val body: ByteArray?, val timeoutNanos: Long)

    /** Stands in for the Cronet transport behind [GoogleTransport.hook]: records what it was given
     *  and answers without going out. */
    private class FakeTransport(private val code: Int = 200, private val finalUrl: String? = null) : Interceptor {
        val seen = AtomicReference<Seen?>()
        override fun intercept(chain: Interceptor.Chain): Response {
            val r = chain.request()
            val body = r.body?.let { b -> Buffer().also { b.writeTo(it) }.readByteArray() }
            seen.set(Seen(r, body, chain.call().timeout().timeoutNanos()))
            val answered = finalUrl?.let { r.newBuilder().url(it).build() } ?: r
            return Response.Builder().request(answered).protocol(Protocol.HTTP_2).code(code).message("")
                .addHeader("Content-Type", "text/plain")
                .addHeader("Set-Cookie", "a=1")
                .addHeader("Set-Cookie", "b=2")
                .body("answer".toResponseBody())
                .build()
        }
    }

    /** The shared client's interceptors, minus the cookie jar and the network. */
    private fun client(transport: Interceptor): OkHttpClient {
        GoogleTransport.interceptor = transport
        return OkHttpClient.Builder()
            .addInterceptor(GoogleTransport.hook)
            .addInterceptor { chain -> transport.intercept(chain) } // a non-Google host ends here too
            .callTimeout(12, TimeUnit.SECONDS)
            .build()
    }

    @After fun tearDown() {
        GoogleTransport.interceptor = null
        GoogleUsage.reset()
    }

    @Test fun headersBodyAndTagsReachTheGoogleTransport() = runBlocking {
        GoogleUsage.reset()
        val transport = FakeTransport()
        val http = OkHttpVelaHttp(client(transport))
        val body = "f.req=%5B%5D&".encodeToByteArray()
        val r = http.call(
            HttpRequest(
                url = "https://www.google.com/maps/rpc/listugcposts?authuser=0",
                method = "POST",
                headers = listOf(
                    HttpHeader("sec-ch-ua", "\"Chromium\";v=\"152\""),
                    HttpHeader("User-Agent", "Mozilla/5.0"),
                    HttpHeader("Accept", "*/*"),
                    HttpHeader("X-Same-Domain", "1"),
                    HttpHeader("X-Twice", "one"),
                    HttpHeader("X-Twice", "two"),
                ),
                body = body,
                contentType = "application/x-www-form-urlencoded;charset=UTF-8",
                tags = RequestTags(usageKind = "reviews", agedSession = true),
            ),
        )
        val seen = transport.seen.get()!!
        assertEquals(
            listOf("sec-ch-ua", "User-Agent", "Accept", "X-Same-Domain", "X-Twice", "X-Twice"),
            (0 until seen.request.headers.size).map { seen.request.headers.name(it) },
        )
        assertEquals(listOf("one", "two"), seen.request.headers("X-Twice"))
        assertEquals("POST", seen.request.method)
        assertArrayEquals(body, seen.body)
        assertEquals("application/x-www-form-urlencoded;charset=UTF-8", seen.request.body!!.contentType().toString())
        assertEquals(AgedSession, seen.request.tag(AgedSession::class.java))
        assertEquals("reviews", seen.request.tag(GoogleUsage.Kind::class.java)?.name)
        assertEquals(1, GoogleUsage.snapshot().values.single()["reviews"])

        assertEquals(200, r.code)
        assertEquals("answer", r.bodyText())
        assertEquals(listOf("a=1", "b=2"), r.headers.filter { it.name == "Set-Cookie" }.map { it.value })
        assertEquals("https://www.google.com/maps/rpc/listugcposts?authuser=0", r.finalUrl)
    }

    @Test fun untaggedRequestCarriesNoTagsAndIsCountedFromItsUrl() = runBlocking {
        GoogleUsage.reset()
        val transport = FakeTransport()
        OkHttpVelaHttp(client(transport)).call(HttpRequest("https://www.google.com/search?tbm=map&q=coffee"))
        val seen = transport.seen.get()!!
        assertEquals("GET", seen.request.method)
        assertNull(seen.body)
        assertNull(seen.request.tag(AgedSession::class.java))
        assertNull(seen.request.tag(GoogleUsage.Kind::class.java))
        assertEquals(1, GoogleUsage.snapshot().values.single()["search"])
    }

    @Test fun statusCodesAndRedirectsAreResponses() = runBlocking {
        val transport = FakeTransport(code = 429, finalUrl = "https://www.google.com/sorry/index")
        val r = OkHttpVelaHttp(client(transport)).call(HttpRequest("https://www.google.com/maps"))
        assertEquals(429, r.code)
        assertEquals("https://www.google.com/sorry/index", r.finalUrl)
    }

    @Test fun timeoutIsTheCallTimeoutTheTransportReads() = runBlocking {
        val transport = FakeTransport()
        val http = OkHttpVelaHttp(client(transport))
        http.call(HttpRequest("https://example.org/", timeoutMillis = 90_000))
        assertEquals(TimeUnit.SECONDS.toNanos(90), transport.seen.get()!!.timeoutNanos)
        http.call(HttpRequest("https://example.org/"))
        assertEquals(TimeUnit.SECONDS.toNanos(12), transport.seen.get()!!.timeoutNanos)
    }

    @Test fun anEmptyPostSendsAnEmptyBody() = runBlocking {
        val transport = FakeTransport()
        OkHttpVelaHttp(client(transport)).call(HttpRequest("https://example.org/", method = "POST"))
        assertArrayEquals(ByteArray(0), transport.seen.get()!!.body)
    }

    @Test fun aBadRequestFailsThroughTheCallback() {
        val error = AtomicReference<Throwable?>()
        OkHttpVelaHttp(OkHttpClient()).execute(HttpRequest("not a url")) { _, e -> error.set(e) }
        assertTrue(error.get() is IllegalArgumentException)
    }

    @Test fun cancelStopsTheCall() {
        val entered = CountDownLatch(1)
        val blocking = Interceptor { chain ->
            entered.countDown()
            while (!chain.call().isCanceled()) Thread.sleep(5)
            throw IOException("canceled")
        }
        val http = OkHttpVelaHttp(OkHttpClient.Builder().addInterceptor(blocking).build())
        val done = CountDownLatch(1)
        val result = AtomicReference<Pair<HttpResponse?, Throwable?>>()
        val handle = http.execute(HttpRequest("https://example.org/")) { r, e -> result.set(r to e); done.countDown() }
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        handle.cancel()
        assertTrue(done.await(5, TimeUnit.SECONDS))
        assertNull(result.get().first)
        assertTrue(result.get().second is IOException)
    }

    @Test fun cancelingTheCoroutineCancelsTheCall() = runBlocking {
        val canceled = CountDownLatch(1)
        val blocking = Interceptor { chain ->
            while (!chain.call().isCanceled()) Thread.sleep(5)
            canceled.countDown()
            throw IOException("canceled")
        }
        val http = OkHttpVelaHttp(OkHttpClient.Builder().addInterceptor(blocking).build())
        val r = runCatching { withTimeout(200) { http.call(HttpRequest("https://example.org/")) } }
        assertTrue(r.exceptionOrNull() is kotlinx.coroutines.TimeoutCancellationException)
        assertTrue(canceled.await(5, TimeUnit.SECONDS))
    }
}
