#import "stream-video-policy.h"
#import <objc/runtime.h>
#import <objc/message.h>

static char deadlineKey, desiredVisibleKey, reasonKey;
static void (*originalSetVisible)(id, SEL, BOOL);
static BOOL (*originalSelect)(id, SEL, NSInteger);
static BOOL (*originalSelectForced)(id, SEL, NSInteger, BOOL);

static BOOL Matches(id object, const char *name, const char *types) {
    Method method = object ? class_getInstanceMethod(object_getClass(object), sel_registerName(name)) : NULL;
    return method && !strcmp(method_getTypeEncoding(method), types);
}
static id Get(id object, const char *name) {
    return Matches(object, name, "@16@0:8") ? ((id (*)(id,SEL))objc_msgSend)(object, sel_registerName(name)) : nil;
}
static BOOL Enabled(id selector) {
    NSNumber *deadline = objc_getAssociatedObject(Get(selector, "delegate"), &deadlineKey);
    return deadline && NSDate.date.timeIntervalSince1970 < deadline.doubleValue;
}
static void RequireVideo(id selector) {
    if (!Enabled(selector)) return;
    if (!objc_getAssociatedObject(selector, &desiredVisibleKey)) {
        BOOL visible = ((BOOL (*)(id,SEL))objc_msgSend)(selector, sel_registerName("visible"));
        objc_setAssociatedObject(selector, &desiredVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    originalSetVisible(selector, sel_registerName("setVisible:"), YES);
}
static void SetVisible(id self, SEL selector, BOOL visible) {
    if (Enabled(self)) {
        objc_setAssociatedObject(self, &desiredVisibleKey, @(visible), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        originalSetVisible(self, selector, YES);
    } else originalSetVisible(self, selector, visible);
}
static BOOL Select(id self, SEL selector, NSInteger reason) {
    objc_setAssociatedObject(self, &reasonKey, @(reason), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    RequireVideo(self); return originalSelect(self, selector, reason);
}
static BOOL SelectForced(id self, SEL selector, NSInteger reason, BOOL force) {
    objc_setAssociatedObject(self, &reasonKey, @(reason), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    RequireVideo(self); return originalSelectForced(self, selector, reason, force);
}
static BOOL Install(void) {
    static BOOL installed; static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = NSClassFromString(@"MLStreamSelector");
        Method visible = class_getInstanceMethod(cls, sel_registerName("visible"));
        Method delegate = class_getInstanceMethod(cls, sel_registerName("delegate"));
        Method set = class_getInstanceMethod(cls, sel_registerName("setVisible:"));
        Method select = class_getInstanceMethod(cls, sel_registerName("selectStreamWithReason:"));
        Method forced = class_getInstanceMethod(cls, sel_registerName("selectStreamWithReason:forceSelection:"));
        if (!visible || !delegate || !set || !select || !forced ||
            strcmp(method_getTypeEncoding(visible), "B16@0:8") || strcmp(method_getTypeEncoding(delegate), "@16@0:8") ||
            strcmp(method_getTypeEncoding(set), "v20@0:8B16") || strcmp(method_getTypeEncoding(select), "B24@0:8q16") ||
            strcmp(method_getTypeEncoding(forced), "B28@0:8q16B24")) return;
        originalSetVisible = (void *)method_getImplementation(set);
        originalSelect = (void *)method_getImplementation(select);
        originalSelectForced = (void *)method_getImplementation(forced);
        method_setImplementation(set, (IMP)SetVisible);
        method_setImplementation(select, (IMP)Select);
        method_setImplementation(forced, (IMP)SelectForced);
        installed = YES;
    });
    return installed;
}
BOOL YTAVEnableStreamVideo(id backend, double deadline) {
    if (!backend || !isfinite(deadline) || deadline <= NSDate.date.timeIntervalSince1970 || !Install()) return NO;
    objc_setAssociatedObject(backend, &deadlineKey, @(deadline), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id selector = Get(backend, "streamSelector");
    if (selector) {
        RequireVideo(selector);
        NSNumber *reason = objc_getAssociatedObject(selector, &reasonKey);
        // If selection already began in audio-only mode, reuse YouTube's actual
        // reason to re-evaluate its own stream set for the visible video output.
        if (reason && !Get(backend, "selectedVideoFormat"))
            originalSelectForced(selector, sel_registerName("selectStreamWithReason:forceSelection:"), reason.integerValue, YES);
    }
    return YES;
}
void YTAVDisableStreamVideo(id backend) {
    if (!backend) return;
    objc_setAssociatedObject(backend, &deadlineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id selector = Get(backend, "streamSelector");
    NSNumber *desired = objc_getAssociatedObject(selector, &desiredVisibleKey);
    if (desired && originalSetVisible) originalSetVisible(selector, sel_registerName("setVisible:"), desired.boolValue);
    if (selector) objc_setAssociatedObject(selector, &desiredVisibleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
