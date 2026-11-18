package app.vela.core.platform

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

class VelaHttpCallTest {
    /** Holds each request's callback until the test answers it. */
    private class FakeHttp : VelaHttp {
        var callback: ((HttpResponse?, Throwable?) -> Unit)? = null
        var request: HttpRequest? = null
        var canceled = 0
        val started = CompletableDeferred<Unit>()

        override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
            this.request = request
            this.callback = callback
            started.complete(Unit)
            return Cancellable { canceled++ }
        }
    }

    private fun ok(body: String = "hi") =
        HttpResponse(200, listOf(HttpHeader("Content-Type", "text/plain")), body.encodeToByteArray(), "https://example.org/")

    @Test fun returnsTheResponse() = runTest {
        val http = FakeHttp()
        val req = HttpRequest("https://example.org/")
        val result = async(start = CoroutineStart.UNDISPATCHED) { http.call(req) }
        http.started.await()
        assertSame(req, http.request)
        http.callback!!(ok("body"), null)
        val r = result.await()
        assertEquals(200, r.code)
        assertEquals("body", r.bodyText())
        assertEquals(0, http.canceled)
    }

    @Test fun answersInsideExecuteToo() = runTest {
        val http = object : VelaHttp {
            override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
                callback(HttpResponse(204, emptyList(), ByteArray(0), request.url), null)
                return Cancellable { }
            }
        }
        assertEquals(204, http.call(HttpRequest("https://example.org/a")).code)
    }

    @Test fun rethrowsTheClientError() = runTest {
        class NetDown : Exception("down")
        val http = FakeHttp()
        val result = async(start = CoroutineStart.UNDISPATCHED) { runCatching { http.call(HttpRequest("https://example.org/")) } }
        http.started.await()
        http.callback!!(null, NetDown())
        val e = result.await().exceptionOrNull()
        assertTrue(e is NetDown, "got $e")
    }

    @Test fun anEmptyCallbackIsAnError() = runTest {
        val http = FakeHttp()
        val result = async(start = CoroutineStart.UNDISPATCHED) { runCatching { http.call(HttpRequest("https://example.org/")) } }
        http.started.await()
        http.callback!!(null, null)
        assertTrue(result.await().exceptionOrNull() is IllegalStateException)
    }

    @Test fun cancelingTheCoroutineCancelsTheRequest() = runTest {
        val http = FakeHttp()
        val job = async(start = CoroutineStart.UNDISPATCHED) { http.call(HttpRequest("https://example.org/")) }
        http.started.await()
        job.cancel()
        yield()
        assertEquals(1, http.canceled)
        assertTrue(job.isCancelled)
        // The client answering after the cancel is ignored.
        http.callback!!(null, Exception("canceled"))
        http.callback!!(ok(), null)
        assertFailsWith<kotlinx.coroutines.CancellationException> { job.await() }
    }

    @Test fun aSecondCallbackIsIgnored() = runTest {
        val http = FakeHttp()
        val result = async(start = CoroutineStart.UNDISPATCHED) { http.call(HttpRequest("https://example.org/")) }
        http.started.await()
        http.callback!!(ok("first"), null)
        http.callback!!(ok("second"), null)
        http.callback!!(null, Exception("late"))
        assertEquals("first", result.await().bodyText())
        assertFalse(result.isCancelled)
    }

    @Test fun headerLookupIsCaseBlindAndTakesTheLast() {
        val r = HttpResponse(
            200,
            listOf(HttpHeader("Set-Cookie", "a=1"), HttpHeader("set-cookie", "b=2")),
            ByteArray(0),
            "https://example.org/",
        )
        assertEquals("b=2", r.header("SET-COOKIE"))
        assertEquals(null, r.header("Location"))
        assertTrue(r.isSuccessful)
        assertFalse(HttpResponse(302, emptyList(), ByteArray(0), "").isSuccessful)
    }

    @Test fun joinPathUsesOneSlash() {
        assertEquals("/data/files/piper/x.onnx", joinPath("/data/files/", "piper", "x.onnx"))
        assertEquals("/data/files", joinPath("/data/files"))
    }
}
