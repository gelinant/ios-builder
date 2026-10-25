// Bridging header of the Vela app target (project.yml SWIFT_OBJC_BRIDGING_HEADER).
#import <JavaScriptCore/JavaScriptCore.h>

// From JavaScriptCore's private JSContextRefPrivate.h, which the SDK does not ship. The symbol is
// exported by the system framework (iOS 7 and later); JavaScriptCoreJsEngine uses it to kill a
// script that runs past its time limit. With a NULL callback the script is terminated
// unconditionally once the group has run for `limit` seconds of CPU time.
typedef bool (*JSShouldTerminateCallback)(JSContextRef ctx, void *context);

JS_EXPORT void JSContextGroupSetExecutionTimeLimit(JSContextGroupRef group, double limit,
    JSShouldTerminateCallback callback, void *context);
