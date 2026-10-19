#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import "speed-state.h"
#import "alert-state.h"
#import "vietmap-alert-assets.h"
#import "test-state.h"
#import "carplay-style.h"
#import "placement-state.h"
#import "diagnostics.h"
#import "background-policy.h"
#import "refresh-loop.h"
#import "source-transport.h"
#import "vietmap-output.h"
#include <notify.h>

static NSHashTable *views;
static NSMapTable *models, *statuses, *nativeInputs, *nativeChildren;
static id applyingNativeModel;
static int testToken = -1, testFirstAlertToken = -1, testSecondAlertToken = -1, testLaneToken = -1, testLaneLimitToken = -1;
static int placementToken = -1;
static BOOL installed;
static int backgroundToken=-1;
static double lastBackgroundHeartbeat=-1;
static NSTimeInterval lastSourceRequest=-1;
static __thread BOOL constructingCarPlay, applyingCarPlay;
static void (*originalModel)(id, SEL, id), (*originalChildModel)(id, SEL, id);
static void (*originalSupports)(id, SEL, BOOL), (*originalDisplay)(id, SEL, BOOL);
static void (*originalSetup)(id, SEL), (*originalSpeedEnabled)(id, SEL, BOOL);
static id (*originalChildInit)(id, SEL, id);
static void (*originalChildLayout)(id, SEL), (*originalMapLayout)(id, SEL);

static void Log(NSString *message) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"googlemaps-vietmap.log"];
    [message writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static BOOL MethodMatches(Class cls, NSString *name, const char *encoding) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    return method && strcmp(method_getTypeEncoding(method), encoding) == 0;
}
static BOOL External(UIView *view) { return view.window && view.window.screen != UIScreen.mainScreen; }
static void PublishBackgroundHeartbeat(UIView *view, BOOL test, double now) {
    static NSString *lastState;
    NSString *state=[NSString stringWithFormat:@"window=%@ scene=%@ activation=%ld app=%ld test=%d token=%d hidden=%d alpha=%.2f boundsEmpty=%d",
        NSStringFromClass(view.window.class),NSStringFromClass(view.window.windowScene.class),
        (long)view.window.windowScene.activationState,(long)UIApplication.sharedApplication.applicationState,
        test,backgroundToken,view.hidden,view.alpha,CGRectIsEmpty(view.bounds)];
    if (![state isEqual:lastState]) {
        lastState=state;
        [state writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-background-client.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    UIWindow *window=view.window;
    UIWindowScene *scene=window.windowScene;
    // Both Google's full-map CPWindow and Dashboard UIWindow lack a UIWindowScene here.
    BOOL active=scene ? scene.activationState==UISceneActivationStateForegroundActive :
        UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
    if (test || backgroundToken<0 || now-lastBackgroundHeartbeat<3 || !active ||
        ![UIScreen.screens containsObject:window.screen] || CGRectIsEmpty(view.bounds)) return;
    for (UIView *ancestor=view; ancestor; ancestor=ancestor.superview)
        if (ancestor.hidden || ancestor.alpha<=0.01) return;
    BOOL resumed=GVMHeartbeatResumed(now,lastBackgroundHeartbeat);
    lastBackgroundHeartbeat=now;
    notify_set_state(backgroundToken,(uint64_t)(now*1000));
    if (resumed) notify_post(GVM_BACKGROUND_SIGNAL);
}
static id Read(id object, NSString *name) { return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name)); }
static void SetBool(id object, NSString *name, BOOL value) { ((void (*)(id, SEL, BOOL))objc_msgSend)(object, NSSelectorFromString(name), value); }

static NSDictionary *TestSample(void) {
    uint64_t state = 0;
    if (testToken < 0 || notify_get_state(testToken, &state) != NOTIFY_STATUS_OK) return nil;
    return GVMDecodeTest(state, NSProcessInfo.processInfo.systemUptime);
}
static int photoToken=-1;
static BOOL PhotoSample(void) {
    uint64_t photo=0, current=0;
    return photoToken>=0 && testToken>=0 && notify_get_state(photoToken,&photo)==NOTIFY_STATUS_OK &&
        notify_get_state(testToken,&current)==NOTIFY_STATUS_OK && photo && photo==current && TestSample();
}
static NSArray<NSDictionary *> *TestAlerts(NSTimeInterval now) {
    NSMutableArray<NSDictionary *> *alerts=[NSMutableArray arrayWithCapacity:2];
    for (int tokenIndex=0;tokenIndex<2;tokenIndex++) {
        int token=tokenIndex==0 ? testFirstAlertToken : testSecondAlertToken;
        uint64_t state=0;
        if (token<0 || notify_get_state(token,&state)!=NOTIFY_STATUS_OK) continue;
        NSDictionary *alert=GVMDecodeAlertWithin(state,now,300);
        NSDictionary *normalized=alert ? GVMVietMapOutputAlert(alert,now) : nil;
        if (normalized) [alerts addObject:normalized];
    }
    return alerts;
}
static NSDictionary *TestSamples(NSDictionary *test, NSTimeInterval now) {
    NSMutableDictionary *samples=[@{@"speed":@{@"value":test[@"speed"],@"receivedAt":@(now)},
        @"speedLimit":@{@"value":test[@"limit"],@"receivedAt":@(now)}} mutableCopy];
    uint64_t state=0, limitState=0;
    NSDictionary *lanes=testLaneToken>=0 && notify_get_state(testLaneToken,&state)==NOTIFY_STATUS_OK ? GVMDecodeTestLanes(state) : nil;
    NSArray *items=lanes[@"items"];
    NSArray<NSNumber *> *limits=items && testLaneLimitToken>=0 && notify_get_state(testLaneLimitToken,&limitState)==NOTIFY_STATUS_OK ?
        GVMDecodeTestLaneLimits(limitState,items.count) : nil;
    if (limits) {
        NSMutableArray *limited=[NSMutableArray new];
        for (NSUInteger i=0;i<items.count;i++) {
            NSMutableDictionary *item=[items[i] mutableCopy]; item[@"limit"]=limits[i];
            [limited addObject:[item copy]];
        }
        items=limited;
    }
    if (lanes) samples[@"lanes"]=@{@"distance":lanes[@"distance"],@"items":items,@"receivedAt":@(now)};
    return samples;
}
static id ModelFor(NSNumber *speed, NSNumber *limit, NSUInteger style, NSInteger unit) {
    // Preserve Google's m/s model units for the VietMap display-value feed.
    double speedMS = speed ? speed.doubleValue / 3.6 : -1;
    double limitMS = limit ? limit.doubleValue / 3.6 : -1;
    // This supported Google build uses 2 for minor speeding; 0/1 share normal colors.
    NSUInteger severity = speed && limit && speed.doubleValue > limit.doubleValue ? 2 : 0;
    return ((id (*)(id, SEL, double, double, NSUInteger, NSInteger, NSUInteger))objc_msgSend)(
        [NSClassFromString(@"GMSNSpeedLimitInfo") alloc],
        NSSelectorFromString(@"initWithSpeedLimit:speed:style:distanceUnit:speedingType:"),
        limitMS, speedMS, style, unit, severity);
}
static void Apply(UIView *view, BOOL forceNative) {
    if (!NSThread.isMainThread || !External(view)) return;
    // Decode each field once so all consumers see the same update.
    NSDictionary *test = TestSample();
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSDictionary *output=test ? GVMSourceOutput(GVMSourceVietMap,TestSamples(test,now),TestAlerts(now),now) : GVMReadSourceOutput(now);
    NSNumber *speed=output[@"speed"][@"value"], *limit=output[@"speedLimit"][@"value"];
    id googleModel=[models objectForKey:view];
    NSUInteger style=googleModel ? ((NSUInteger (*)(id,SEL))objc_msgSend)(googleModel,NSSelectorFromString(@"style")) : 1;
    NSInteger unit=googleModel ? ((NSInteger (*)(id,SEL))objc_msgSend)(googleModel,NSSelectorFromString(@"distanceUnit")) : 1;
    NSArray *inputs=@[speed ?: NSNull.null,limit ?: NSNull.null,@(style),@(unit)];
    id child=Read(view,@"speedLimitView");
    BOOL nativeChanged=forceNative || !child || [nativeChildren objectForKey:view]!=child ||
        ![[nativeInputs objectForKey:view] isEqual:inputs];
    BOOL prior=applyingCarPlay; id priorModel=applyingNativeModel;
    applyingCarPlay=YES;
    @try {
        // Google may change these flags without replacing its model.
        SetBool(view,@"setSupportsHeadingView:",NO);
        SetBool(view,@"setShouldDisplayHeadingView:",NO);
        if (nativeChanged) {
            originalSupports(view,NSSelectorFromString(@"setSupportsSpeedLimitView:"),YES);
            originalDisplay(view,NSSelectorFromString(@"setShouldDisplaySpeedLimitView:"),YES);
            applyingNativeModel=ModelFor(speed,limit,style,unit);
            originalModel(view,NSSelectorFromString(@"setSpeedLimitInfo:"),applyingNativeModel);
            child=Read(view,@"speedLimitView");
            if (child) {
                [nativeInputs setObject:inputs forKey:view];
                [nativeChildren setObject:child forKey:view];
            }
        }
        if (child) {
            SetBool(child,@"setSpeedometerEnabled:",YES);
            GVMStyleNativeSpeedView(child);
        }
        PublishBackgroundHeartbeat(view,test!=nil,now);
        if (GVMShouldRequestSource(now,lastSourceRequest,!view.hidden && view.alpha>0, test!=nil,
                                  !speed || !limit)) {
            lastSourceRequest=now;
            if (GVMRequestSelectedSource()) GVMDiagnosticsRecord(GVMDiagnosticRequest,1);
        }
        GVMUpdateSpeedCard(view,output,
            ((BOOL (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"nightModeMap")));
        GVMDiagnosticsRecord(GVMDiagnosticCarPlay,(speed ? 1 : 0) | (limit ? 2 : 0) | (test ? 4 : 0));
        NSString *status = [NSString stringWithFormat:@"CarPlay mode=%@ speed=%@ limit=%@ window=%@ child=%@ bounds=%@ safe=%@ windowSafe=%@ screen=%@",
            test ? @"TEST" : @"live",
            speed ?: @"unavailable",limit ?: @"unavailable",
            NSStringFromClass(view.window.class), child ? NSStringFromClass([child class]) : @"none",
            NSStringFromCGRect(view.bounds),NSStringFromUIEdgeInsets(view.safeAreaInsets),
            NSStringFromUIEdgeInsets(view.window.safeAreaInsets),NSStringFromCGRect(view.window.screen.bounds)];
        if (![[statuses objectForKey:view] isEqual:status]) {
            Log(status); [statuses setObject:status forKey:view];
        }
    } @finally { applyingCarPlay = prior; applyingNativeModel=priorModel; }
    GVMSetSpeedCardTest(view, test && !PhotoSample());
    if (nativeChanged) [view setNeedsLayout];
}
static void SetModel(id self, SEL selector, id info) {
    if (!NSThread.isMainThread) { originalModel(self, selector, info); return; }
    [views addObject:self];
    if ([info isKindOfClass:NSClassFromString(@"GMSNSpeedLimitInfo")]) [models setObject:info forKey:self];
    if (External(self)) Apply(self,YES); else originalModel(self, selector, info);
}
static void SetChildModel(id self, SEL selector, id info) {
    // The native CarPlay setter can strip speed when a Google feature flag is off.
    // Replace at its existing child model boundary only during our CarPlay update.
    if (applyingCarPlay && applyingNativeModel) info=applyingNativeModel;
    originalChildModel(self, selector, info);
}
static void SetSupports(id self, SEL selector, BOOL value) {
    if (!NSThread.isMainThread) { originalSupports(self, selector, value); return; }
    originalSupports(self, selector, value || External(self));
}
static void SetDisplay(id self, SEL selector, BOOL value) {
    if (!NSThread.isMainThread) { originalDisplay(self, selector, value); return; }
    originalDisplay(self, selector, value || External(self));
}
static void Setup(id self, SEL selector) {
    BOOL prior = constructingCarPlay; constructingCarPlay = NSThread.isMainThread;
    @try { originalSetup(self, selector); } @finally { constructingCarPlay = prior; }
}
static id InitChild(id self, SEL selector, id configuration) {
    if (constructingCarPlay && [configuration isKindOfClass:NSClassFromString(@"GMSNSpeedLimitViewConfiguration")]) {
        configuration = [configuration copy];
        SetBool(configuration, @"setSpeedometerCapable:", YES);
    }
    return originalChildInit(self, selector, configuration);
}
static void SetSpeedEnabled(id self, SEL selector, BOOL value) {
    if (applyingCarPlay) value = YES;
    originalSpeedEnabled(self, selector, value);
}
static void LayoutChild(id self, SEL selector) {
    originalChildLayout(self, selector);
    GVMStyleNativeSpeedView(self);
}
static void LayoutMap(id self, SEL selector) {
    originalMapLayout(self, selector);
    GVMLayoutSpeedCard(self);
}
static void Install(void) {
    if (installed) return;
    Class map = NSClassFromString(@"AZCarPlayView"), child = NSClassFromString(@"GMSNSpeedLimitView");
    Class info = NSClassFromString(@"GMSNSpeedLimitInfo"), configuration = NSClassFromString(@"GMSNSpeedLimitViewConfiguration");
    if (!map || !child || !info || !configuration) { GVMDiagnosticsRecord(GVMDiagnosticHook,2); return; }
    if (!MethodMatches(map, @"setSpeedLimitInfo:", "v24@0:8@16") ||
        !MethodMatches(map, @"setSupportsSpeedLimitView:", "v20@0:8B16") ||
        !MethodMatches(map, @"setShouldDisplaySpeedLimitView:", "v20@0:8B16") ||
        !MethodMatches(map, @"setSupportsHeadingView:", "v20@0:8B16") ||
        !MethodMatches(map, @"setShouldDisplayHeadingView:", "v20@0:8B16") ||
        !MethodMatches(map, @"setupSpeedLimitViewIfNeeded", "v16@0:8") ||
        !MethodMatches(map, @"supportsSpeedLimitView", "B16@0:8") ||
        !MethodMatches(map, @"shouldDisplaySpeedLimitView", "B16@0:8") ||
        !MethodMatches(map, @"layoutSubviews", "v16@0:8") ||
        !MethodMatches(map, @"nightModeMap", "B16@0:8") ||
        !MethodMatches(map, @"speedLimitView", "@16@0:8") ||
        !MethodMatches(child, @"setSpeedLimitInfo:", "v24@0:8@16") ||
        !MethodMatches(child, @"setSpeedometerEnabled:", "v20@0:8B16") ||
        !MethodMatches(child, @"initWithConfiguration:", "@24@0:8@16") ||
        !MethodMatches(child, @"layoutSubviews", "v16@0:8") ||
        !MethodMatches(configuration, @"setSpeedometerCapable:", "v20@0:8B16") ||
        !MethodMatches(info, @"initWithSpeedLimit:speed:style:distanceUnit:speedingType:", "@56@0:8d16d24Q32q40Q48") ||
        !MethodMatches(info, @"style", "Q16@0:8") || !MethodMatches(info, @"distanceUnit", "q16@0:8")) {
        GVMDiagnosticsRecord(GVMDiagnosticHook,3); Log(@"unsupported Google Maps ABI; replacement inactive"); return;
    }
    notify_register_check(GVM_BACKGROUND_SIGNAL,&backgroundToken);
    // Test transport failure must not disable the production source.
    notify_register_check(GVMTestStateName, &testToken);
    notify_register_check("com.chou.googlemaps.vietmap.test.photo", &photoToken);
    notify_register_check(GVMTestFirstAlertStateName, &testFirstAlertToken);
    notify_register_check(GVMTestSecondAlertStateName, &testSecondAlertToken);
    notify_register_check(GVMTestLaneStateName, &testLaneToken);
    notify_register_check(GVMTestLaneLimitStateName, &testLaneLimitToken);
    views = [NSHashTable weakObjectsHashTable]; models = [NSMapTable weakToStrongObjectsMapTable];
    statuses = [NSMapTable weakToStrongObjectsMapTable];
    nativeInputs=[NSMapTable weakToStrongObjectsMapTable];
    nativeChildren=[NSMapTable weakToWeakObjectsMapTable];
    notify_register_dispatch(GVMPlacementStateName, &placementToken,
        dispatch_get_main_queue(), ^(int token) {
            uint64_t state=0;
            if (notify_get_state(token,&state)==NOTIFY_STATUS_OK) GVMSetPlacementState(state);
            for (UIView *view in views.allObjects) Apply(view,NO);
        });
    uint64_t placementState=0;
    if (placementToken>=0 && notify_get_state(placementToken,&placementState)==NOTIFY_STATUS_OK)
        GVMSetPlacementState(placementState);
    MSHookMessageEx(map, NSSelectorFromString(@"setSpeedLimitInfo:"), (IMP)SetModel, (IMP *)&originalModel);
    MSHookMessageEx(map, NSSelectorFromString(@"setSupportsSpeedLimitView:"), (IMP)SetSupports, (IMP *)&originalSupports);
    MSHookMessageEx(map, NSSelectorFromString(@"setShouldDisplaySpeedLimitView:"), (IMP)SetDisplay, (IMP *)&originalDisplay);
    MSHookMessageEx(map, NSSelectorFromString(@"setupSpeedLimitViewIfNeeded"), (IMP)Setup, (IMP *)&originalSetup);
    MSHookMessageEx(child, NSSelectorFromString(@"initWithConfiguration:"), (IMP)InitChild, (IMP *)&originalChildInit);
    MSHookMessageEx(child, NSSelectorFromString(@"setSpeedLimitInfo:"), (IMP)SetChildModel, (IMP *)&originalChildModel);
    MSHookMessageEx(child, NSSelectorFromString(@"setSpeedometerEnabled:"), (IMP)SetSpeedEnabled, (IMP *)&originalSpeedEnabled);
    MSHookMessageEx(map, @selector(layoutSubviews), (IMP)LayoutMap, (IMP *)&originalMapLayout);
    MSHookMessageEx(child, @selector(layoutSubviews), (IMP)LayoutChild, (IMP *)&originalChildLayout);
    installed = YES;
    GVMDiagnosticsRecord(GVMDiagnosticHook,1);
    Log(@"native CarPlay replacement loaded 0.1.8; awaiting fresh VietMap samples");
}
void GVMRefreshCarPlayViews(void) {
    if (!installed) return;
    @try { for (UIView *view in views.allObjects) Apply(view,NO); }
    @catch (NSException *exception) { GVMDiagnosticsRecord(GVMDiagnosticError,1); Log([@"refresh refused: " stringByAppendingString:exception.name]); }
}
static void ImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ Install(); });
}
__attribute__((constructor)) static void Start(void) {
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.google.Maps"]) {
        GVMDiagnosticsStart(@"googlemaps");
        _dyld_register_func_for_add_image(ImageLoaded);
    }
}
