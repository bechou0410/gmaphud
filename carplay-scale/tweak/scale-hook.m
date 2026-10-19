// Draws the CarPlay main screen at a smaller point scale so more content fits. CarPlay.app builds the display
// configuration that CarPlay and the apps it hosts lay out against; the video stream keeps its pixels.
// Built without ARC: the hooked method is an initializer, and the FrontBoard copies are returned +1.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <notify.h>
#include <unistd.h>
#import "scale-math.h"

static const int64_t TrustedAfterSeconds = 10;
static SEL copyWithModeSelector, copyModeSelector, pointScaleSelector, pixelSizeSelector, carSelector, carInstrumentsSelector;
static id (*originalInit)(id, SEL, id, id, BOOL);
static CGFloat appliedRatio;
static BOOL scalingBlocked;

// Settings saves through cfprefsd, which CarPlay.app can read; synchronizing picks up a change made moments ago.
static CGFloat SavedRatio(void) {
    CFStringRef domain = CFSTR(CPS_PREFERENCES_DOMAIN);
    CFPreferencesAppSynchronize(domain);
    NSNumber *enabled = [(id)CFPreferencesCopyAppValue(CFSTR("enabled"), domain) autorelease];
    NSNumber *percent = [(id)CFPreferencesCopyAppValue(CFSTR("percent"), domain) autorelease];
    return CPSRatioFromPreferences(enabled, percent);
}

static void SetUnconfirmedLaunches(NSInteger launches) {
    CFStringRef domain = CFSTR(CPS_PREFERENCES_DOMAIN);
    CFPreferencesSetAppValue(CFSTR(CPS_UNCONFIRMED_LAUNCHES_KEY), launches ? (CFNumberRef)@(launches) : NULL, domain);
    CFPreferencesAppSynchronize(domain);
}

// Stops a crash loop: every launch that scales counts itself until it has run for a while. After two launches
// in a row that never got that far, scaling stays off until Settings saves again (which clears the count).
static BOOL LaunchIsTrusted(void) {
    NSNumber *saved = [(id)CFPreferencesCopyAppValue(CFSTR(CPS_UNCONFIRMED_LAUNCHES_KEY), CFSTR(CPS_PREFERENCES_DOMAIN)) autorelease];
    NSInteger launches = [saved isKindOfClass:NSNumber.class] ? saved.integerValue : 0;
    if (launches >= 2) return NO;
    SetUnconfirmedLaunches(launches + 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, TrustedAfterSeconds * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ SetUnconfirmedLaunches(0); });
    return YES;
}

static id Value(id object, NSString *key) {
    @try { return [object valueForKey:key]; } @catch (NSException *exception) { return nil; }
}

// Returns a +1 copy of the configuration drawn at the applied ratio, or nil to keep the original.
static id CopyScaledConfiguration(id configuration) {
    id mode = Value(configuration, @"currentMode");
    if (![mode respondsToSelector:copyModeSelector] || ![mode respondsToSelector:pointScaleSelector] || ![mode respondsToSelector:pixelSizeSelector]) return nil;
    CGFloat nativeScale = ((CGFloat (*)(id, SEL))objc_msgSend)(mode, pointScaleSelector);
    CGSize pixels = ((CGSize (*)(id, SEL))objc_msgSend)(mode, pixelSizeSelector);
    CPSScaledMode scaled = CPSMakeScaledMode(pixels, nativeScale, appliedRatio);
    if (!scaled.valid) return nil;
    id scaledMode = ((id (*)(id, SEL, CGSize, CGFloat))objc_msgSend)(mode, copyModeSelector, scaled.pointSize, scaled.scale);
    id copy = scaledMode ? ((id (*)(id, SEL, id))objc_msgSend)(configuration, copyWithModeSelector, scaledMode) : nil;
    [scaledMode release];
    // A subclass caller must get its own class back, so only plain configurations are replaced.
    if (copy && object_getClass(copy) != object_getClass(configuration)) {
        [copy release];
        return nil;
    }
    return copy;
}

// FrontBoard's own classification: the CarPlay screen, not an instrument cluster. Head units name their screens
// differently (CarPlay Simulator uses "VideoStream.Main"), so the screen identifier cannot be relied on.
static BOOL IsCarMainScreen(id configuration) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(configuration, carSelector) && !((BOOL (*)(id, SEL))objc_msgSend)(configuration, carInstrumentsSelector);
}

static void RecordCarScreen(id configuration, id applied) {
    NSString *record = [NSString stringWithFormat:@"%@ %@ -> %@", Value(Value(configuration, @"CADisplay"), @"uniqueId"),
        Value(configuration, @"currentMode"), applied ? Value(applied, @"currentMode") : @"unchanged"];
    CFPreferencesSetAppValue(CFSTR(CPS_LAST_CAR_SCREEN_KEY), (CFStringRef)record, CFSTR(CPS_PREFERENCES_DOMAIN));
    CFPreferencesAppSynchronize(CFSTR(CPS_PREFERENCES_DOMAIN));
}

static id HookedInit(id self, SEL command, id immutableDisplay, id originalDisplay, BOOL assertIfInvalid) {
    id configuration = originalInit(self, command, immutableDisplay, originalDisplay, assertIfInvalid);
    if (!configuration || !IsCarMainScreen(configuration)) return configuration;
    // CarPlay.app outlives CarPlay sessions; reading again here lets a choice saved without Apply take effect
    // when the screen is rebuilt for the next connection.
    if (!scalingBlocked) appliedRatio = SavedRatio();
    id copy = appliedRatio > 0 ? CopyScaledConfiguration(configuration) : nil;
    RecordCarScreen(configuration, copy);
    if (!copy) return configuration;
    NSLog(@"[CarPlayScale] %@ -> %@", Value(configuration, @"currentMode"), Value(copy, @"currentMode"));
    [configuration release];
    return copy;
}

// A new size only takes effect when CarPlay.app rebuilds its displays, so it quits and the system relaunches it.
static void RestartIfChanged(void) {
    CGFloat saved = SavedRatio();
    if (saved == appliedRatio) return;
    NSLog(@"[CarPlayScale] ratio %.2f -> %.2f, restarting CarPlay", appliedRatio, saved);
    SetUnconfirmedLaunches(0);
    _exit(0);
}

__attribute__((constructor)) static void Install(void) {
    @autoreleasepool {
        Class configuration = NSClassFromString(@"FBSDisplayConfiguration"), mode = NSClassFromString(@"FBSDisplayMode");
        SEL initSelector = NSSelectorFromString(@"_initWithImmutableDisplay:originalDisplay:assertIfInvalid:");
        copyWithModeSelector = NSSelectorFromString(@"copyWithOverrideMode:");
        copyModeSelector = NSSelectorFromString(@"_copyWithOverrideSize:scale:");
        pointScaleSelector = NSSelectorFromString(@"pointScale");
        pixelSizeSelector = NSSelectorFromString(@"pixelSize");
        carSelector = NSSelectorFromString(@"isCarDisplay");
        carInstrumentsSelector = NSSelectorFromString(@"isCarInstrumentsDisplay");
        if (![configuration instancesRespondToSelector:initSelector] || ![configuration instancesRespondToSelector:copyWithModeSelector] ||
            ![configuration instancesRespondToSelector:carSelector] || ![configuration instancesRespondToSelector:carInstrumentsSelector] ||
            ![mode instancesRespondToSelector:copyModeSelector] || ![mode instancesRespondToSelector:pointScaleSelector] || ![mode instancesRespondToSelector:pixelSizeSelector]) {
            NSLog(@"[CarPlayScale] FrontBoard interface not found; scaling disabled");
            return;
        }
        // Registered before reading, so a change saved in between is not missed.
        int token;
        notify_register_dispatch(CPS_CHANGED_NOTIFICATION, &token, dispatch_get_main_queue(), ^(__unused int fired) { RestartIfChanged(); });
        appliedRatio = SavedRatio();
        if (appliedRatio > 0 && !LaunchIsTrusted()) {
            NSLog(@"[CarPlayScale] CarPlay restarted twice soon after scaling; scaling stays off until Settings saves again");
            appliedRatio = 0;
            scalingBlocked = YES;
        }
        MSHookMessageEx(configuration, initSelector, (IMP)HookedInit, (IMP *)&originalInit);
    }
}
