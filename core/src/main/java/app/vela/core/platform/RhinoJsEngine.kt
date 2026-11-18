package app.vela.core.platform

import org.mozilla.javascript.Context
import org.mozilla.javascript.ContextFactory
import org.mozilla.javascript.Function
import org.mozilla.javascript.ScriptableObject

/**
 * [JsEngine] over a locked-down Rhino sandbox: runs one function out of a JavaScript source and
 * returns its String result (or null on anything going wrong). Pure (no Android / DI), so it's
 * unit-testable on the JVM.
 *
 *  - `initSafeStandardObjects` exposes **no** Java (`Packages`/reflection/IO): the
 *    script can only read and return the string it's handed.
 *  - `optimizationLevel = -1` (interpreted): Rhino's bytecode generator doesn't run on
 *    Android/ART, so we never emit classes.
 *  - **Wall-clock kill switch** (the caller's time limit, 2 s from `JsTransforms`): a private
 *    [ContextFactory] arms Rhino's instruction observer; a script that runs longer (an accidental
 *    `while(true)` in a pushed `transforms.js`) throws, which the `runCatching` below turns into
 *    the documented compiled-Kotlin fallback. Without it a runaway script hangs the calling
 *    search forever AND, via `synchronized(this)`, blocks every subsequent transform.
 *  - `synchronized`: Rhino contexts aren't thread-safe; serialize all use.
 *  - Any exception (parse error, missing function, wrong return type, timeout) → null, so
 *    the caller falls back to compiled Kotlin.
 */
object RhinoJsEngine : JsEngine {
    private val deadlineNanos = ThreadLocal<Long>()
    private val limitMillis = ThreadLocal<Long>()

    private val factory = object : ContextFactory() {
        override fun makeContext(): Context = super.makeContext().apply {
            optimizationLevel = -1 // interpreted: required on ART, and instruction-observed
            languageVersion = Context.VERSION_ES6
            instructionObserverThreshold = 10_000 // observe every ~10k bytecodes
        }

        override fun observeInstructionCount(cx: Context, instructionCount: Int) {
            val deadline = deadlineNanos.get() ?: return
            if (System.nanoTime() > deadline) {
                // Error (not Exception) so the sandboxed JS can't try/catch its way past the kill.
                throw Error("transforms.js exceeded ${limitMillis.get()}ms")
            }
        }
    }

    override fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String? = synchronized(this) {
        runCatching {
            deadlineNanos.set(System.nanoTime() + timeLimitMillis * 1_000_000L)
            limitMillis.set(timeLimitMillis)
            val cx = factory.enterContext()
            try {
                val scope = cx.initSafeStandardObjects()
                cx.evaluateString(scope, source, "transforms.js", 1, null)
                val f = ScriptableObject.getProperty(scope, function) as? Function ?: return@runCatching null
                val result = f.call(cx, scope, scope, arrayOf<Any>(argument))
                (Context.jsToJava(result, String::class.java) as? String)?.takeIf { it.isNotBlank() }
            } finally {
                Context.exit()
                deadlineNanos.remove()
                limitMillis.remove()
            }
        }.getOrNull()
    }
}
