import Foundation
import JavaScriptCore
import VelaCore

/// The `JsEngine` seam over JavaScriptCore's C API (PORTAGE_IOS.md D6, SPEC "Platform seams"). One
/// context group for the process; each call gets a fresh global context with the standard objects
/// only (no host object, no timers, no network), released afterward. The time limit is the group's
/// watchdog (`JSContextGroupSetExecutionTimeLimit`, Vela-Bridging-Header.h), which the script cannot
/// catch: the evaluation gets the whole limit, the call what is left of it. Calls are serialized;
/// after a timeout the group is replaced.
final class JavaScriptCoreJsEngine: NSObject, VelaCore.JsEngine {
    private var group: JSContextGroupRef = JSContextGroupCreate()
    private let lock = NSLock()

    deinit {
        JSContextGroupRelease(group)
    }

    func call(source: String, function: String, argument: String, timeLimitMillis: Int64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let limit = max(Double(timeLimitMillis), 1) / 1000
        let started = DispatchTime.now().uptimeNanoseconds
        let out = run(source: source, function: function, argument: argument, limit: limit, started: started)
        // A group whose watchdog fired is not reused, in case the termination outlives the
        // context it hit.
        if out == nil && seconds(since: started) >= limit * 0.9 {
            JSContextGroupRelease(group)
            group = JSContextGroupCreate()
        }
        return out
    }

    private func run(source: String, function: String, argument: String, limit: Double, started: UInt64) -> String? {
        guard let ctx = JSGlobalContextCreateInGroup(group, nil) else { return nil }
        defer { JSGlobalContextRelease(ctx) }
        var exception: JSValueRef?

        JSContextGroupSetExecutionTimeLimit(group, limit, nil, nil)
        let script = JSStringCreateWithCFString(source as CFString)
        defer { JSStringRelease(script) }
        _ = JSEvaluateScript(ctx, script, nil, nil, 1, &exception)
        guard exception == nil else { return nil }

        let remaining = limit - seconds(since: started)
        guard remaining > 0 else { return nil }
        JSContextGroupSetExecutionTimeLimit(group, remaining, nil, nil)

        let name = JSStringCreateWithCFString(function as CFString)
        defer { JSStringRelease(name) }
        let value = JSObjectGetProperty(ctx, JSContextGetGlobalObject(ctx), name, &exception)
        guard exception == nil, let value, JSValueIsObject(ctx, value),
              let fn = JSValueToObject(ctx, value, nil), JSObjectIsFunction(ctx, fn) else { return nil }

        let arg = JSStringCreateWithCFString(argument as CFString)
        defer { JSStringRelease(arg) }
        var args: [JSValueRef?] = [JSValueMakeString(ctx, arg)]
        let result = JSObjectCallAsFunction(ctx, fn, nil, 1, &args, &exception)
        guard exception == nil, let result, JSValueIsString(ctx, result),
              let text = JSValueToStringCopy(ctx, result, nil) else { return nil }
        defer { JSStringRelease(text) }
        guard let copied = JSStringCopyCFString(kCFAllocatorDefault, text) else { return nil }
        let out = copied as String
        return out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : out
    }

    private func seconds(since started: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
    }
}
