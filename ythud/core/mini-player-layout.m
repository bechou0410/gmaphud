#import "mini-player-layout.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "runtime-mode.h"

@interface YTAVMiniLayoutInput : NSObject
- (instancetype)initWithSizeClass:(NSInteger)sizeClass aspectRatio:(double)ratio smallestWindowDimension:(double)dimension
    parentBounds:(CGRect)bounds appLeftOffset:(double)left appRightOffset:(double)right appBottomOffset:(double)bottom
    appTopOffset:(double)top minimumDefaultDimension:(double)minimum snapPosition:(NSInteger)snap scale:(id)scale
    dockableMiniplayerPercentage:(double)dockable dockedYPercentage:(id)docked transientInput:(id)transient variant:(NSInteger)variant;
@end

static id (*originalLayout)(id, SEL, id);
static BOOL (*trialEnabled)(void);
static unsigned loggedRepairs;
static const char *initializer = "initWithSizeClass:aspectRatio:smallestWindowDimension:parentBounds:appLeftOffset:appRightOffset:appBottomOffset:appTopOffset:minimumDefaultDimension:snapPosition:scale:dockableMiniplayerPercentage:dockedYPercentage:transientInput:variant:";

static double Number(id object, const char *name) { return ((double (*)(id,SEL))objc_msgSend)(object, sel_registerName(name)); }
static NSInteger Integer(id object, const char *name) { return ((NSInteger (*)(id,SEL))objc_msgSend)(object, sel_registerName(name)); }
static id Object(id object, const char *name) { return ((id (*)(id,SEL))objc_msgSend)(object, sel_registerName(name)); }
static double ExternalDimension(CGRect bounds) {
    if (!isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width <= 1 || bounds.size.height <= 1) return 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.screen == UIScreen.mainScreen) continue;
        for (UIWindow *window in windowScene.windows)
            if (!window.hidden && window.alpha >= .01 && fabs(window.bounds.size.width-bounds.size.width) <= 1 &&
                fabs(window.bounds.size.height-bounds.size.height) <= 1) return MIN(bounds.size.width, bounds.size.height);
    }
    return 0;
}
static id Layout(id self, SEL selector, id input) {
    if (!input || !trialEnabled || !trialEnabled() || !NSThread.isMainThread) return originalLayout(self, selector, input);
    double dimension = Number(input, "smallestWindowDimension");
    if (isfinite(dimension) && dimension > 0) return originalLayout(self, selector, input);
    CGRect bounds = ((CGRect (*)(id,SEL))objc_msgSend)(input, sel_registerName("parentBounds"));
    double repaired = ExternalDimension(bounds);
    if (!repaired) return originalLayout(self, selector, input);
    // The native layout reads the value object's internal storage directly.
    // Reconstruct its input with the missing metric, preserving every other field.
    id corrected = [(YTAVMiniLayoutInput *)[[input class] alloc]
        initWithSizeClass:Integer(input, "sizeClass") aspectRatio:Number(input, "aspectRatio") smallestWindowDimension:repaired
        parentBounds:bounds appLeftOffset:Number(input, "appLeftOffset") appRightOffset:Number(input, "appRightOffset")
        appBottomOffset:Number(input, "appBottomOffset") appTopOffset:Number(input, "appTopOffset")
        minimumDefaultDimension:Number(input, "minimumDefaultDimension") snapPosition:Integer(input, "snapPosition")
        scale:Object(input, "scale") dockableMiniplayerPercentage:Number(input, "dockableMiniplayerPercentage")
        dockedYPercentage:Object(input, "dockedYPercentage") transientInput:Object(input, "transientInput") variant:Integer(input, "variant")];
    if (!YTAV_RELEASE && corrected && loggedRepairs++ < 32) {
        NSString *line = [NSString stringWithFormat:@"%.3f dimension=%.3f repaired=%.3f parent=%@\n",
            NSDate.date.timeIntervalSince1970, dimension, repaired, NSStringFromCGRect(bounds)];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ytav-mini-fix.log"];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSData.data writeToFile:path atomically:YES];
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
        [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
    }
    return originalLayout(self, selector, corrected ?: input);
}
static BOOL Signature(Class cls, const char *name, const char *types) {
    Method method = class_getInstanceMethod(cls, sel_registerName(name));
    return method && !strcmp(method_getTypeEncoding(method), types);
}
void YTAVInstallMiniPlayerLayout(BOOL (*enabled)(void)) {
    Class input = NSClassFromString(@"YTWatchMiniplayerLayoutInput");
    Method layout = class_getClassMethod(NSClassFromString(@"YTWatchMiniplayerLayoutUtils"), sel_registerName("layoutWithInput:"));
    if (!layout || strcmp(method_getTypeEncoding(layout), "@24@0:8@16") ||
        !Signature(input, initializer, "@160@0:8q16d24d32{CGRect={CGPoint=dd}{CGSize=dd}}40d72d80d88d96d104q112@120d128@136@144q152") ||
        !Signature(input, "parentBounds", "{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8")) return;
    for (NSString *name in @[@"smallestWindowDimension", @"aspectRatio", @"appLeftOffset", @"appRightOffset", @"appBottomOffset", @"appTopOffset", @"minimumDefaultDimension", @"dockableMiniplayerPercentage"])
        if (!Signature(input, name.UTF8String, "d16@0:8")) return;
    for (NSString *name in @[@"sizeClass", @"snapPosition", @"variant"])
        if (!Signature(input, name.UTF8String, "q16@0:8")) return;
    for (NSString *name in @[@"scale", @"dockedYPercentage", @"transientInput"])
        if (!Signature(input, name.UTF8String, "@16@0:8")) return;
    trialEnabled = enabled;
    originalLayout = (void *)method_getImplementation(layout);
    method_setImplementation(layout, (IMP)Layout);
}
