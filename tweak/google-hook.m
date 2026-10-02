#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import "speed-state.h"
#import "test-state.h"
#import "carplay-style.h"
#include <notify.h>

static NSHashTable *views;
static NSMapTable *models, *statuses;
static int speedToken = -1, limitToken = -1, testToken = -1;
static BOOL installed;
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
static BOOL KnownImage(void) {
    NSString *path = NSBundle.mainBundle.executablePath.stringByResolvingSymlinksInPath;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || ![[[NSString stringWithUTF8String:name] stringByResolvingSymlinksInPath] isEqual:path]) continue;
        const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
        if (!header || header->magic != MH_MAGIC_64 || header->sizeofcmds > 1048576) return NO;
        const uint8_t *cursor = (const void *)(header + 1), *end = cursor + header->sizeofcmds;
        for (uint32_t j = 0; j < header->ncmds; j++) {
            if ((size_t)(end - cursor) < sizeof(struct load_command)) return NO;
            const struct load_command *command = (const void *)cursor;
            if (command->cmdsize < sizeof(*command) || command->cmdsize > (size_t)(end - cursor)) return NO;
            if (command->cmd == LC_UUID && command->cmdsize >= sizeof(struct uuid_command)) {
                NSUUID *uuid = [[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid];
                return [uuid.UUIDString isEqual:@"E8BB60A0-E434-3412-AC6B-9B6800E031A6"];
            }
            cursor += command->cmdsize;
        }
    }
    return NO;
}
static BOOL External(UIView *view) { return view.window && view.window.screen != UIScreen.mainScreen; }
static NSNumber *Value(int token, BOOL zero) {
    uint64_t state = 0;
    if (token < 0 || notify_get_state(token, &state) != NOTIFY_STATUS_OK) return nil;
    return GVMDecodeSample(state, NSProcessInfo.processInfo.systemUptime, zero);
}
static id Read(id object, NSString *name) { return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name)); }
static void SetBool(id object, NSString *name, BOOL value) { ((void (*)(id, SEL, BOOL))objc_msgSend)(object, NSSelectorFromString(name), value); }

static NSDictionary *TestSample(void) {
    uint64_t state = 0;
    if (testToken < 0 || notify_get_state(testToken, &state) != NOTIFY_STATUS_OK) return nil;
    return GVMDecodeTest(state, NSProcessInfo.processInfo.systemUptime);
}
static id ModelFor(id view) {
    NSDictionary *test = TestSample();
    NSNumber *speed = test ? test[@"speed"] : Value(speedToken, YES);
    NSNumber *limit = test ? test[@"limit"] : Value(limitToken, NO);
    id prior = [models objectForKey:view];
    NSUInteger style = prior ? ((NSUInteger (*)(id, SEL))objc_msgSend)(prior, NSSelectorFromString(@"style")) : 1;
    NSInteger unit = prior ? ((NSInteger (*)(id, SEL))objc_msgSend)(prior, NSSelectorFromString(@"distanceUnit")) : 1;
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
static void Apply(UIView *view) {
    if (!NSThread.isMainThread || !External(view)) return;
    originalSupports(view, NSSelectorFromString(@"setSupportsSpeedLimitView:"), YES);
    originalDisplay(view, NSSelectorFromString(@"setShouldDisplaySpeedLimitView:"), YES);
    SetBool(view, @"setSupportsHeadingView:", NO);
    SetBool(view, @"setShouldDisplayHeadingView:", NO);
    BOOL prior = applyingCarPlay; applyingCarPlay = YES;
    @try {
        originalModel(view, NSSelectorFromString(@"setSpeedLimitInfo:"), ModelFor(view));
        id child = Read(view, @"speedLimitView");
        if (child) {
            SetBool(child, @"setSpeedometerEnabled:", YES);
            GVMStyleNativeSpeedView(child);
        }
        NSDictionary *test = TestSample();
        GVMUpdateSpeedCard(view, test ? test[@"speed"] : Value(speedToken, YES),
            test ? test[@"limit"] : Value(limitToken, NO),
            ((BOOL (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"nightModeMap")));
        NSString *status = [NSString stringWithFormat:@"CarPlay mode=%@ speed=%@ limit=%@ window=%@ child=%@",
            test ? @"TEST" : @"live",
            (test ? test[@"speed"] : Value(speedToken, YES)) ?: @"unavailable",
            (test ? test[@"limit"] : Value(limitToken, NO)) ?: @"unavailable",
            NSStringFromClass(view.window.class), child ? NSStringFromClass([child class]) : @"none"];
        if (![[statuses objectForKey:view] isEqual:status]) {
            Log(status); [statuses setObject:status forKey:view];
        }
    } @finally { applyingCarPlay = prior; }
    static const void *testLabelKey = &testLabelKey;
    UILabel *label = objc_getAssociatedObject(view, testLabelKey);
    if (TestSample() && !label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = @"TEST"; label.font = [UIFont boldSystemFontOfSize:9];
        label.textColor = UIColor.blackColor; label.backgroundColor = UIColor.systemYellowColor;
        label.textAlignment = NSTextAlignmentCenter; label.layer.cornerRadius = 4; label.clipsToBounds = YES;
        label.userInteractionEnabled = NO;
        [view addSubview:label]; objc_setAssociatedObject(view, testLabelKey, label, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    label.hidden = !TestSample();
    CGRect cardFrame = GVMLayoutSpeedCard(view);
    label.frame = CGRectMake(CGRectGetMaxX(cardFrame)-36, CGRectGetMaxY(cardFrame)+3, 36, 13);
    if (!label.hidden) [view bringSubviewToFront:label];
    [view setNeedsLayout];
}
static void SetModel(id self, SEL selector, id info) {
    if (!NSThread.isMainThread) { originalModel(self, selector, info); return; }
    [views addObject:self];
    if ([info isKindOfClass:NSClassFromString(@"GMSNSpeedLimitInfo")]) [models setObject:info forKey:self];
    if (External(self)) Apply(self); else originalModel(self, selector, info);
}
static void SetChildModel(id self, SEL selector, id info) {
    // The native CarPlay setter can strip speed when a Google feature flag is off.
    // Replace at its existing child model boundary only during our CarPlay update.
    if (applyingCarPlay) {
        UIView *owner = self;
        while (owner && ![owner isKindOfClass:NSClassFromString(@"AZCarPlayView")]) owner = owner.superview;
        if (owner) info = ModelFor(owner);
    }
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
    if (!KnownImage()) { Log(@"unsupported Google Maps build; replacement inactive"); return; }
    Class map = NSClassFromString(@"AZCarPlayView"), child = NSClassFromString(@"GMSNSpeedLimitView");
    Class info = NSClassFromString(@"GMSNSpeedLimitInfo"), configuration = NSClassFromString(@"GMSNSpeedLimitViewConfiguration");
    if (!map || !child || !info || !configuration) return;
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
        Log(@"unsupported Google Maps ABI; replacement inactive"); return;
    }
    if (notify_register_check(GVMSpeedStateName, &speedToken) != NOTIFY_STATUS_OK ||
        notify_register_check(GVMLimitStateName, &limitToken) != NOTIFY_STATUS_OK) {
        Log(@"speed transport unavailable; replacement inactive"); return;
    }
    // Test transport failure must not disable the production source.
    notify_register_check(GVMTestStateName, &testToken);
    views = [NSHashTable weakObjectsHashTable]; models = [NSMapTable weakToStrongObjectsMapTable];
    statuses = [NSMapTable weakToStrongObjectsMapTable];
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
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        @try { for (UIView *view in views.allObjects) Apply(view); }
        @catch (NSException *exception) { Log([@"refresh refused: " stringByAppendingString:exception.name]); }
    }];
    Log(@"native CarPlay replacement loaded 0.1.8; awaiting fresh VietMap samples");
}
static void ImageLoaded(const struct mach_header *header, intptr_t slide) {
    (void)header; (void)slide;
    dispatch_async(dispatch_get_main_queue(), ^{ Install(); });
}
__attribute__((constructor)) static void Start(void) {
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.google.Maps"])
        _dyld_register_func_for_add_image(ImageLoaded);
}
