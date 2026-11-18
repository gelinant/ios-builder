#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/// Debug UI-test entry point for the GO screen. The map screen belongs to other lots, so a new
/// screen cannot add its own presentation line there; this constructor registers one launch-time
/// observer and does nothing unless `-VelaTransitGoTest` is present. It never runs in a normal
/// launch, and it does not touch production state.
__attribute__((constructor))
static void VelaTransitGoTestBootstrap(void) {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (![arguments containsObject:@"-VelaTransitGoTest"]) {
        return;
    }
    [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            Class support = NSClassFromString(@"TransitGoTestSupport");
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
