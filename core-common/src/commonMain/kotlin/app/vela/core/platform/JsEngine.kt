package app.vela.core.platform

/**
 * A locked-down JavaScript engine for the signed `transforms.js` (SPEC "Platform seams"). Android:
 * Rhino, interpreted, safe standard objects only. iOS: JavaScriptCore, with the limit set by
 * `JSContextGroupSetExecutionTimeLimit`.
 *
 * The script sees only the string it is handed: no host objects, no reflection, no IO, no network.
 */
interface JsEngine {
    /**
     * Evaluates [source] in a fresh global scope, then calls its global function [function] with
     * the one string argument [argument] and returns the result converted to a string.
     *
     * Returns null when anything goes wrong: a syntax error, a thrown exception, no such function,
     * a result that is not a string, a blank result, or a run longer than [timeLimitMillis] wall
     * clock milliseconds (evaluation and call together). The limit cannot be caught by the script:
     * a `while(true){}` returns null after about [timeLimitMillis]. Calls may come from any thread;
     * the implementation serializes them.
     */
    fun call(source: String, function: String, argument: String, timeLimitMillis: Long): String?
}
