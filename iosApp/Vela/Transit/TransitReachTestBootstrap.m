#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// Debug UI-test entry point for the "Reachable in N minutes" screen. The map screen belongs to
/// other lots, so this constructor registers one launch-time observer and does nothing unless
/// `-VelaTransitReachTest` is present. It never runs in a normal launch.
__attribute__((constructor))
static void VelaTransitReachTestBootstrap(void) {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (![arguments containsObject:@"-VelaTransitReachTest"]) {
        return;
    }
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Class support = NSClassFromString(@"TransitReachTestSupport");
            if (support == Nil) {
                return;
            }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [support performSelector:@selector(present)];
#pragma clang diagnostic pop
        });
    }];
}
