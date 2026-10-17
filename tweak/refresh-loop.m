#import "refresh-loop.h"
#import "source-transport.h"

static double lastRefresh;
static void Refresh(void) {
    lastRefresh=NSProcessInfo.processInfo.systemUptime;
    GVMRefreshCarPlayViews();
    GVMRefreshPhoneOverlay();
}
__attribute__((constructor)) static void StartRefreshLoop(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Maps"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // The poll keeps expiry and reconnect checks running when no source posts.
        NSTimer *timer=[NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) { Refresh(); }];
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
        // A committed frame shows at once, coalesced to at most ten refreshes a second.
        static BOOL pending;
        GVMObserveSourceOutput(dispatch_get_main_queue(), ^{
            if (pending) return;
            pending=YES;
            double wait=MAX(0,0.1-(NSProcessInfo.processInfo.systemUptime-lastRefresh));
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(wait*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
                pending=NO; Refresh();
            });
        });
    });
}
