#import "playback-state.h"
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL Matches(id object, const char *name, const char *encoding) {
    Method method = object ? class_getInstanceMethod(object_getClass(object), sel_registerName(name)) : NULL;
    return method && !strcmp(method_getTypeEncoding(method), encoding);
}
static id Get(id object, const char *name) {
    return Matches(object, name, "@16@0:8") ? ((id (*)(id,SEL))objc_msgSend)(object, sel_registerName(name)) : nil;
}
static NSNumber *Rate(id object) {
    float rate = Matches(object, "rate", "f16@0:8") ? ((float (*)(id,SEL))objc_msgSend)(object, sel_registerName("rate")) : -1;
    return @(isfinite(rate) ? rate : -1);
}
NSDictionary *YTAVPlaybackState(id backend, AVPlayer *displayPlayer) {
    id asset = Get(backend, "assetPlayer");
    AVPlayer *primary = Get(asset, "player");
    if (![primary isKindOfClass:AVPlayer.class]) primary = nil;
    double clock = displayPlayer.currentItem.timebase ? CMTimebaseGetRate(displayPlayer.currentItem.timebase) : 0;
    return @{ @"backendRate": Rate(backend), @"assetRate": Rate(asset), @"primaryRate": Rate(primary),
        @"primaryPlayer": [NSString stringWithFormat:@"%p", primary],
        @"primarySharesItem": @(primary && primary.currentItem == displayPlayer.currentItem),
        @"streamVideoVisible": @(Matches(Get(backend, "streamSelector"), "visible", "B16@0:8") ?
            ((BOOL (*)(id,SEL))objc_msgSend)(Get(backend, "streamSelector"), sel_registerName("visible")) : -1),
        @"timeControlStatus": @(displayPlayer.timeControlStatus), @"clockRate": @(isfinite(clock) ? clock : 0) };
}
NSDictionary *YTAVRefreshPlaybackObservers(id backend, AVPlayer *displayPlayer) {
    id asset = Get(backend, "assetPlayer");
    AVPlayer *primary = Get(asset, "player");
    if (![primary isKindOfClass:AVPlayer.class] || !displayPlayer.currentItem ||
        primary.currentItem != displayPlayer.currentItem ||
        !Matches(asset, "currentTimeDidChange:", "v40@0:8{?=qiIq}16") ||
        !Matches(asset, "play", "v16@0:8") || !Matches(asset, "pause", "v16@0:8"))
        return @{ @"skipped": @"source-or-abi" };
    // The wrapper's rate is a playback speed, even while paused. Preserve it.
    // Reconcile actual playback through its existing play/pause and time observer paths.
    NSMutableDictionary *result = [NSMutableDictionary new];
    @try {
        ((void (*)(id,SEL,CMTime))objc_msgSend)(asset, sel_registerName("currentTimeDidChange:"), primary.currentTime);
        result[@"time"] = @YES;
    } @catch (NSException *e) { result[@"timeError"] = e.reason ?: e.name; }
    double clock = primary.currentItem.timebase ? CMTimebaseGetRate(primary.currentItem.timebase) : 0;
    @try {
        if (clock > .01 && primary.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
            ((void (*)(id,SEL))objc_msgSend)(asset, sel_registerName("play"));
            result[@"state"] = @"playing";
        } else if (clock == 0 && primary.rate == 0 && primary.timeControlStatus == AVPlayerTimeControlStatusPaused) {
            ((void (*)(id,SEL))objc_msgSend)(asset, sel_registerName("pause"));
            result[@"state"] = @"paused";
        }
    } @catch (NSException *e) { result[@"rateError"] = e.reason ?: e.name; }
    return result;
}
