#import <UIKit/UIKit.h>
#import "carplay-style.h"
#import "speed-state.h"
#import "alert-state.h"
#import "refresh-loop.h"
#import "background-policy.h"
#import "source-transport.h"
#include <notify.h>

static int backgroundToken=-1;
static __weak UIView *phoneHost;
static double lastRequest=-1;
static double lastHeartbeat=-1;
static UIView *ForegroundHost(void) {
    UIApplication *app=UIApplication.sharedApplication;
    if (app.applicationState!=UIApplicationStateActive) return nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen==UIScreen.mainScreen && window.isKeyWindow && !window.hidden &&
                window.alpha>0.01 && window.windowLevel==UIWindowLevelNormal && window.rootViewController) {
                // Use the entire app window; navigation controllers can inset their root view.
                return window;
            }
        }
    }
    return nil;
}
void GVMRefreshPhoneOverlay(void) {
    UIView *host=ForegroundHost();
    if (phoneHost!=host) { GVMRemovePhoneSpeedCard(phoneHost); phoneHost=host; }
    if (!host) {
        // Let the heartbeat expire instead of clearing it, so a brief banner, Control Center
        // or app switch does not end the source session while the phone map is in use.
        lastHeartbeat=-1;
        return;
    }
    double now=NSProcessInfo.processInfo.systemUptime;
    if (backgroundToken>=0 && (lastHeartbeat<0 || now-lastHeartbeat>=3)) {
        BOOL resumed=GVMHeartbeatResumed(now,lastHeartbeat);
        notify_set_state(backgroundToken,(uint64_t)(now*1000)); lastHeartbeat=now;
        if (resumed) notify_post(GVM_BACKGROUND_PHONE_SIGNAL);
    }
    NSDictionary *output=GVMReadSourceOutput(now);
    NSNumber *speed=output[@"speed"][@"value"], *limit=output[@"speedLimit"][@"value"];
    if (GVMShouldRequestSource(now,lastRequest,YES,NO,!speed || !limit)) {
        lastRequest=now; GVMRequestSelectedSource();
    }
    GVMUpdatePhoneSpeedCard(host,output,host.traitCollection.userInterfaceStyle==UIUserInterfaceStyleDark);
}
__attribute__((constructor)) static void StartPhone(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.google.Maps"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        notify_register_check(GVM_BACKGROUND_PHONE_SIGNAL,&backgroundToken);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            GVMRemovePhoneSpeedCard(phoneHost); phoneHost=nil;
            lastHeartbeat=-1;
        }];
    });
}
