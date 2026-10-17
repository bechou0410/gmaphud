#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "output-channel.h"

// This host has no scene-setting APIs and accepts only a complete 960x540 root.
static UIView *overlay;
static CALayer *host;
static NSFileHandle *events;
static double start;
static YTAVOutputChannel channel = { -1, -1, -1, false };
static unsigned lastContext;
static BOOL Visible(UIView *view) {
    if (!view.window) return NO;
    for (UIView *v = view; v; v = v.superview) if (v.hidden || v.alpha < .01) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window], view.window.bounds);
}
static void Find(UIView *view, NSMutableArray *matches, unsigned depth, unsigned *budget) {
    if (!view || depth > 32 || !*budget) return;
    --*budget; unsigned buttons = 0; BOOL progress = NO;
    for (UIView *child in view.subviews) {
        NSString *name = NSStringFromClass(child.class);
        if ([name isEqualToString:@"DBNowPlayingFocusHighlightButton"]) buttons++;
        if ([name isEqualToString:@"CPUIProgressView"]) progress = YES;
    }
    if (buttons == 3 && progress && Visible(view) && view.bounds.size.width > 100 && view.bounds.size.height > 60) [matches addObject:view];
    for (UIView *child in view.subviews) Find(child, matches, depth+1, budget);
}
static void Remove(void) { [overlay removeFromSuperview]; overlay = nil; host = nil; lastContext = 0; }
static void Log(NSString *text) {
    if (YTAV_RELEASE) return;
    if (events.offsetInFile < 2 * 1024 * 1024) {
        NSString *line = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, text];
        [events writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
}
static BOOL Signature(id object, const char *name, const char *encoding) {
    Method method = class_getInstanceMethod(object_getClass(object), sel_registerName(name));
    return method && !strcmp(method_getTypeEncoding(method), encoding);
}
static id ReadObject(id object, const char *name) {
    if (!Signature(object, name, "@16@0:8")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel_registerName(name));
}
static BOOL OpenYouTube(UIView *view, BOOL activate) {
    @try {
        UIViewController *widget = nil;
        Class widgetClass = NSClassFromString(@"DBNowPlayingWidgetViewController");
        UIResponder *responder = view;
        for (unsigned depth = 0; responder && depth < 32; depth++, responder = responder.nextResponder) {
            if (widgetClass && [responder isKindOfClass:widgetClass]) { widget = (UIViewController *)responder; break; }
        }
        id environment = ReadObject(widget, "environment");
        Class dashboardClass = NSClassFromString(@"DBDashboard");
        if (!dashboardClass || ![environment isKindOfClass:dashboardClass] ||
            !Signature(environment, "_launchAppWithInfo:forURL:", "v32@0:8@16@24")) return NO;
        id controller = ReadObject(NSClassFromString(@"DBApplicationController"), "sharedInstance");
        if (!Signature(controller, "applicationWithBundleIdentifier:", "@24@0:8@16")) return NO;
        id application = ((id (*)(id, SEL, id))objc_msgSend)(controller,
            sel_registerName("applicationWithBundleIdentifier:"), @"com.google.ios.youtube");
        if (![ReadObject(application, "bundleIdentifier") isEqual:@"com.google.ios.youtube"]) return NO;
        Class launchInfoClass = NSClassFromString(@"DBApplicationLaunchInfo");
        if (!Signature(launchInfoClass, "launchInfoForApplication:", "@24@0:8@16")) return NO;
        if (activate) {
            id info = ((id (*)(id, SEL, id))objc_msgSend)(launchInfoClass,
                sel_registerName("launchInfoForApplication:"), application);
            if (![info isKindOfClass:launchInfoClass]) return NO;
            ((void (*)(id, SEL, id, id))objc_msgSend)(environment,
                sel_registerName("_launchAppWithInfo:forURL:"), info, nil);
            Log(@"TAP opened-youtube-on-carplay");
        }
        return YES;
    } @catch (NSException *exception) {
        Log([@"TAP failed " stringByAppendingString:exception.name]); return NO;
    }
}
static BOOL CurrentOutput(void) {
    unsigned context = 0;
    return overlay && Visible(overlay) && lastContext &&
        YTAVChannelExport(&channel, &context) && context == lastContext;
}
@interface YTAVDashboardVideoButton : UIButton
@end
@implementation YTAVDashboardVideoButton
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // Unsupported launch routes and withdrawn outputs keep native tile hit testing.
    return [super pointInside:point withEvent:event] && CurrentOutput() && OpenYouTube(self, NO);
}
- (void)openYouTube {
    if (CurrentOutput()) OpenYouTube(self, YES);
}
@end
static void Update(void) {
    NSMutableOrderedSet *windows = [NSMutableOrderedSet new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
    NSMutableArray *matches = [NSMutableArray new]; unsigned budget = 1200;
    for (UIWindow *window in windows) Find(window, matches, 0, &budget);
    BOOL visible = matches.count == 1 && budget;
    if (!YTAVChannelHostPublish(&channel, visible)) { Remove(); Log(@"CHANNEL host-publish-failed"); return; }
    if (!visible) { Remove(); return; }
    unsigned context = 0;
    BOOL automatic = YTAVChannelExport(&channel, &context);
    if (!automatic) {
        if (YTAV_RELEASE) { Remove(); return; }
        NSDictionary *c = [NSDictionary dictionaryWithContentsOfFile:@"/var/tmp/ytav-output-host.plist"];
        double now = NSDate.date.timeIntervalSince1970, issued = [c[@"issuedAt"] doubleValue], end = [c[@"expires"] doubleValue];
        unsigned long long manualContext = [c[@"contextID"] unsignedLongLongValue];
        if (!isfinite(issued) || !isfinite(end) || issued > now || end <= now || end-issued > 180 || end <= issued ||
            !manualContext || manualContext > UINT32_MAX || c[@"holdSourceScene"] || c[@"sourceX"] || c[@"sourceY"]) { Remove(); return; }
        context = (unsigned)manualContext;
    }
    UIView *target = matches.firstObject; CGFloat bottom = CGRectGetMaxY(target.bounds);
    for (UIView *child in target.subviews)
        if ([NSStringFromClass(child.class) isEqualToString:@"CPUIProgressView"]) bottom = MIN(bottom, CGRectGetMinY(child.frame)-3);
    if (bottom <= 0) { Remove(); return; }
    if (overlay.superview != target) {
        Remove(); host = [NSClassFromString(@"CALayerHost") layer];
        Method m = class_getInstanceMethod(object_getClass(host), sel_registerName("setContextId:"));
        if (!m || strcmp(method_getTypeEncoding(m), "v20@0:8I16")) { host = nil; return; }
        YTAVDashboardVideoButton *button = [YTAVDashboardVideoButton new];
        [button addTarget:button action:@selector(openYouTube) forControlEvents:UIControlEventPrimaryActionTriggered];
        button.accessibilityLabel = @"Open YouTube";
        overlay = button; overlay.backgroundColor = UIColor.blackColor;
        overlay.clipsToBounds = YES; [target addSubview:overlay]; [overlay.layer addSublayer:host];
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    overlay.frame = CGRectMake(0, 0, target.bounds.size.width, bottom);
    CGFloat scale = MIN(overlay.bounds.size.width/960, overlay.bounds.size.height/540);
    host.bounds = CGRectMake(0,0,960,540); host.anchorPoint = CGPointZero;
    host.position = CGPointMake((overlay.bounds.size.width-960*scale)/2,(overlay.bounds.size.height-540*scale)/2);
    host.transform = CATransform3DMakeScale(scale,scale,1);
    ((void (*)(id,SEL,unsigned))objc_msgSend)(host, sel_registerName("setContextId:"), (unsigned)context);
    [CATransaction commit];
    if (lastContext != context) {
        Log([NSString stringWithFormat:@"HOST context=%u automatic=%d root=960x540 sceneHold=0 windowCrop=0", context, automatic]);
        lastContext = context;
    }
}
__attribute__((constructor)) static void Begin(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        start = NSDate.date.timeIntervalSince1970;
        if (!YTAV_RELEASE) {
            NSString *path = @"/var/tmp/ytav-output-dashboard.log";
            [NSData.data writeToFile:path atomically:YES]; events = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        __block NSTimer *timer;
        timer = [NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(__unused NSTimer *t) {
            @try {
                if (!YTAV_RELEASE && (NSDate.date.timeIntervalSince1970-start > 1800 || [NSFileManager.defaultManager fileExistsAtPath:@"/var/tmp/ytav-output-dashboard-stop"])) {
                    Remove(); if (channel.open) notify_set_state(channel.dashboard, 0); YTAVChannelClose(&channel);
                    [timer invalidate]; timer = nil; Log(@"STOP"); return;
                }
                Update();
            } @catch (NSException *e) {
                Remove(); if (channel.open) notify_set_state(channel.dashboard, 0); YTAVChannelClose(&channel);
                Log([@"EXCEPTION " stringByAppendingString:e.name]); [timer invalidate]; timer = nil;
            }
        }];
        Log(@"BEGIN no-scene-control-linked");
    });
}
