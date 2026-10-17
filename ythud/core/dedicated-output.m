#import "dedicated-output.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>
#import "output-channel.h"
#import "paused-frame.h"
#import "playback-state.h"
#import "stream-video-policy.h"
#import <float.h>

static id outputContext;
static CALayer *outputRoot, *preview;
static AVPlayerLayer *outputLayer;
static AVPlayer *outputPlayer;
static AVPlayerItem *outputItem;
static __weak AVPlayerLayer *sourceLayer;
static __weak UIView *sourceView;
static double token, highestToken, expires;
static BOOL sawBackground, policyChanged;
static AVPlayerAudiovisualBackgroundPlaybackPolicy previousPolicy;
static NSFileHandle *events;
static YTAVOutputChannel channel = { -1, -1, -1, false };
static YTAVPausedFrame *pausedFrame;
static __weak id sourceBackend, candidateBackend, pendingBackend;
static __weak AVPlayer *candidatePlayer;
static __weak AVPlayerLayer *candidateLayer;
static __weak UIView *candidateView;
static __weak AVPlayerItem *candidateItem;
static double candidateStamp, exportStarted;
static BOOL automatic, wantsContinue, wantsBackgroundVideo;
static double lastStateWrite;
static AVPlayerTimeControlStatus lastTimeControl;
static NSArray *lifecycleObservers;
static unsigned observedCount;
static id observedBackend;
static AVPlayer *observedPlayer;
static AVPlayerLayer *observedLayer;
static UIView *observedView;
static unsigned selectedCount;
static id selectedBackend;
static AVPlayer *selectedPlayer;
static AVPlayerLayer *selectedLayer;
static UIView *selectedView;
static double missingSourceSince;
static char backgroundExportKey;
static BOOL (*originalVideoAllowed)(id, SEL);
static BOOL (*originalShouldDetach)(id, SEL);

static BOOL BackgroundExportEnabled(id player) {
    NSNumber *deadline = objc_getAssociatedObject(player, &backgroundExportKey);
    return deadline && NSDate.date.timeIntervalSince1970 < deadline.doubleValue;
}
static BOOL VideoAllowed(id player, SEL selector) {
    return BackgroundExportEnabled(player) || originalVideoAllowed(player, selector);
}
static BOOL ShouldDetach(id player, SEL selector) {
    return !BackgroundExportEnabled(player) && originalShouldDetach(player, selector);
}

static NSString *Path(NSString *name) { return [NSTemporaryDirectory() stringByAppendingPathComponent:name]; }
static BOOL Matches(id object, const char *name, const char *encoding) {
    Method m = object ? class_getInstanceMethod(object_getClass(object), sel_registerName(name)) : NULL;
    return m && strcmp(method_getTypeEncoding(m), encoding) == 0;
}
static void Event(NSString *text) {
    if (YTAV_RELEASE) return;
    if (!events) {
        NSString *path = Path(@"ytav-output.log");
        [NSData.data writeToFile:path atomically:YES];
        events = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    if (events.offsetInFile < 2 * 1024 * 1024) {
        NSString *line = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, text];
        [events writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
}
static unsigned ContextID(id context) {
    return Matches(context, "contextId", "I16@0:8") ? ((unsigned (*)(id,SEL))objc_msgSend)(context, sel_registerName("contextId")) : 0;
}
static NSNumber *BoolState(id object, const char *name) {
    return Matches(object, name, "B16@0:8") ? @(((BOOL (*)(id,SEL))objc_msgSend)(object, sel_registerName(name))) : @(-1);
}
static BOOL InstallBackgroundExport(AVPlayer *player) {
    if (!Matches(player, "_isVideoPlaybackAllowedWhileInBackground", "B16@0:8") ||
        !Matches(player, "_shouldDetachVideoLayersFromFigPlayer", "B16@0:8")) return NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method allowed = class_getInstanceMethod(AVPlayer.class, sel_registerName("_isVideoPlaybackAllowedWhileInBackground"));
        Method detach = class_getInstanceMethod(AVPlayer.class, sel_registerName("_shouldDetachVideoLayersFromFigPlayer"));
        // AVFoundation can call either hook concurrently as soon as it is installed.
        originalVideoAllowed = (void *)method_getImplementation(allowed);
        originalShouldDetach = (void *)method_getImplementation(detach);
        if (originalVideoAllowed && originalShouldDetach) {
            method_setImplementation(allowed, (IMP)VideoAllowed);
            method_setImplementation(detach, (IMP)ShouldDetach);
        }
    });
    return originalVideoAllowed && originalShouldDetach;
}
static BOOL VisibleSource(UIView *view) {
    UIWindow *window = view.window;
    if (!window || window.windowScene.activationState != UISceneActivationStateForegroundActive ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        view.bounds.size.width <= 1 || view.bounds.size.height <= 1) return NO;
    for (UIView *v = view; v; v = v.superview) if (v.hidden || v.alpha < .01) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:window], window.bounds);
}
static NSDictionary *Command(void) {
    if (YTAV_RELEASE) {
        static NSDictionary *configuration;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            configuration = @{ @"enabled": @YES, @"issuedAt": @(NSDate.date.timeIntervalSince1970),
                @"expires": @(DBL_MAX), @"automaticDashboard": @YES,
                @"continueIfPossible": @YES, @"allowBackgroundVideo": @YES };
        });
        return configuration;
    }
    NSDictionary *command = [NSDictionary dictionaryWithContentsOfFile:Path(@"ytav-output-command.plist")];
    double now = NSDate.date.timeIntervalSince1970;
    double issued = [command[@"issuedAt"] doubleValue], end = [command[@"expires"] doubleValue];
    double maximum = [command[@"automaticDashboard"] boolValue] ? 1800 : 180;
    return [command[@"enabled"] boolValue] && isfinite(issued) && isfinite(end) && issued <= now &&
        now < end && end > issued && end - issued <= maximum ? command : nil;
}
static NSDictionary *State(NSString *status) {
    NSMutableArray *scenes = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scenes.count >= 8) break;
        [scenes addObject:@{ @"state": @(scene.activationState), @"role": scene.session.role ?: @"?" }];
    }
    UIWindow *window = sourceView.window;
    double time = outputPlayer ? CMTimeGetSeconds(outputPlayer.currentTime) : -1;
    return @{ @"status": status, @"stamp": @(NSDate.date.timeIntervalSince1970), @"pid": @(getpid()),
        @"issuedAt": @(token), @"expires": @(expires), @"contextID": @(ContextID(outputContext)),
        @"width": @960, @"height": @540, @"root": [NSString stringWithFormat:@"%p", outputRoot],
        @"exportLayer": [NSString stringWithFormat:@"%p", outputLayer],
        @"exportPlayer": [NSString stringWithFormat:@"%p", outputLayer.player],
        @"sourcePlayer": [NSString stringWithFormat:@"%p", sourceLayer.player],
        @"player": [NSString stringWithFormat:@"%p", outputPlayer], @"item": [NSString stringWithFormat:@"%p", outputPlayer.currentItem],
        @"time": @(isfinite(time) ? time : -1), @"rate": @(outputPlayer.rate),
        @"ready": @(outputLayer.readyForDisplay), @"itemStatus": @(outputPlayer.currentItem.status),
        @"appState": @(UIApplication.sharedApplication.applicationState), @"scenes": scenes,
        @"sourceSceneState": @(window.windowScene ? window.windowScene.activationState : -99),
        @"sawBackground": @(sawBackground), @"sceneHold": @NO, @"windowCrop": @NO,
        @"automatic": @(automatic), @"frozenPicture": @(pausedFrame.frozen),
        @"selectedCount": @(selectedCount), @"sourceBounds": NSStringFromCGRect(sourceView.bounds),
        @"playback": YTAVPlaybackState(sourceBackend, outputPlayer),
        @"videoAllowedInBackground": BoolState(outputPlayer, "_isVideoPlaybackAllowedWhileInBackground"),
        @"shouldDetach": BoolState(outputPlayer, "_shouldDetachVideoLayersFromFigPlayer"),
        @"backgroundVideoOverride": @(BackgroundExportEnabled(outputPlayer)),
        @"originalVideoAllowed": @(outputPlayer && originalVideoAllowed ? originalVideoAllowed(outputPlayer, sel_registerName("_isVideoPlaybackAllowedWhileInBackground")) : -1),
        @"originalShouldDetach": @(outputPlayer && originalShouldDetach ? originalShouldDetach(outputPlayer, sel_registerName("_shouldDetachVideoLayersFromFigPlayer")) : -1),
        @"hasForegroundLayers": BoolState(outputPlayer, "_hasForegroundLayers"),
        @"hasOnscreenLayer": BoolState(outputPlayer, "_hasAssociatedOnscreenAVPlayerLayer"),
        @"pausesInBackground": BoolState(outputPlayer, "_pausesAudioVisualPlaybackInBackground"),
        @"exportSceneForeground": BoolState(outputLayer, "_isPartOfForegroundScene"),
        @"exportSecondScreen": BoolState(outputLayer, "_isConnectedToSecondScreen"),
        @"outputObscured": @(outputPlayer.outputObscuredDueToInsufficientExternalProtection),
        @"policy": @(outputPlayer.audiovisualBackgroundPlaybackPolicy) };
}
static void WriteState(NSString *status) {
    if (YTAV_RELEASE) return;
    NSDictionary *state = State(status);
    [state writeToFile:Path(@"ytav-output-state.plist") atomically:YES];
    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingSortedKeys error:nil];
    if (json) Event([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
}

void YTAVStopDedicatedOutput(NSString *reason) {
    if (!outputContext) return;
    YTAVDisableStreamVideo(sourceBackend); YTAVDisableStreamVideo(pendingBackend); pendingBackend = nil;
    Event([@"END " stringByAppendingString:reason]);
    WriteState(@"ending");
    objc_setAssociatedObject(outputPlayer, &backgroundExportKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (automatic) YTAVChannelWithdraw(&channel);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [preview removeFromSuperlayer]; preview = nil;
    [pausedFrame.layer removeFromSuperlayer]; pausedFrame = nil;
    outputLayer.player = nil;
    BOOL sourceForeground = UIApplication.sharedApplication.applicationState == UIApplicationStateActive && sourceView.window.windowScene &&
        sourceView.window.windowScene.activationState == UISceneActivationStateForegroundActive;
    if (sourceLayer && (sourceLayer.player == outputPlayer || (!sourceLayer.player && sourceForeground))) {
        // Rebinding returns video presentation to the original YouTube layer.
        sourceLayer.player = nil; sourceLayer.player = outputPlayer;
    }
    if (policyChanged && outputPlayer.audiovisualBackgroundPlaybackPolicy == AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible)
        outputPlayer.audiovisualBackgroundPlaybackPolicy = previousPolicy;
    if (sourceForeground && outputPlayer.currentItem == outputItem) {
        @try {
            Event([NSString stringWithFormat:@"REFRESH observers=%@ state=%@", YTAVRefreshPlaybackObservers(sourceBackend, outputPlayer),
                YTAVPlaybackState(sourceBackend, outputPlayer)]);
        } @catch (NSException *e) { Event([NSString stringWithFormat:@"REFRESH_FAILED %@ %@", e.name, e.reason]); }
    }
    Event([NSString stringWithFormat:@"RESTORE player=%p item=%p sourcePlayer=%p policy=%ld backgroundOverride=%d",
        outputPlayer, outputPlayer.currentItem, sourceLayer.player, (long)outputPlayer.audiovisualBackgroundPlaybackPolicy,
        BackgroundExportEnabled(outputPlayer)]);
    ((void (*)(id,SEL,id))objc_msgSend)(outputContext, sel_registerName("setLayer:"), nil);
    ((void (*)(id,SEL))objc_msgSend)(outputContext, sel_registerName("invalidate"));
    [CATransaction commit];
    outputLayer = nil; outputRoot = nil; outputPlayer = nil; outputItem = nil; outputContext = nil;
    sourceLayer = nil; sourceView = nil; sourceBackend = nil; policyChanged = NO;
    WriteState(@"stopped");
}

static void RestorePlayerPolicy(void) {
    objc_setAssociatedObject(outputPlayer, &backgroundExportKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (policyChanged && outputPlayer.audiovisualBackgroundPlaybackPolicy == AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible)
        outputPlayer.audiovisualBackgroundPlaybackPolicy = previousPolicy;
    policyChanged = NO;
}
static void AdoptPlayer(id backend, AVPlayer *player, AVPlayerLayer *layer, UIView *view) {
    AVPlayer *old = outputPlayer;
    AVPlayerItem *oldItem = outputItem;
    if (backend != sourceBackend) YTAVDisableStreamVideo(sourceBackend);
    YTAVEnableStreamVideo(backend, expires);
    if (pendingBackend && pendingBackend != backend) YTAVDisableStreamVideo(pendingBackend);
    pendingBackend = nil;
    if (player != outputPlayer) {
        RestorePlayerPolicy();
        outputPlayer = player;
        previousPolicy = player.audiovisualBackgroundPlaybackPolicy;
        policyChanged = wantsContinue;
        if (policyChanged) player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible;
        if (wantsBackgroundVideo && InstallBackgroundExport(player))
            objc_setAssociatedObject(player, &backgroundExportKey, @(expires), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    outputItem = player.currentItem;
    sourceBackend = backend; sourceLayer = layer; sourceView = view;
    lastTimeControl = player.timeControlStatus;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    outputLayer.player = nil;
    [pausedFrame.layer removeFromSuperlayer]; pausedFrame = [YTAVPausedFrame new];
    pausedFrame.layer.frame = outputRoot.bounds;
    if (layer.player == player) [pausedFrame captureFromLayer:layer];
    outputLayer.player = player;
    [outputRoot addSublayer:pausedFrame.layer];
    [CATransaction commit]; [CATransaction flush];
    missingSourceSince = 0;
    Event([NSString stringWithFormat:@"ADOPT context=%u oldPlayer=%p oldItem=%p player=%p item=%p backend=%p original=%p",
        ContextID(outputContext), old, oldItem, player, outputItem, backend, layer]);
}

static BOOL Begin(id backend, AVPlayer *player, AVPlayerLayer *layer, UIView *view, NSDictionary *command) {
    Class cls = NSClassFromString(@"CAContext");
    if (!Matches(cls, "remoteContextWithOptions:", "@24@0:8@16")) { Event(@"REJECT context-factory-abi"); return NO; }
    NSMutableDictionary *options = [NSMutableDictionary dictionary];
    NSString *__unsafe_unretained *ignoreKey = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, "kCAContextIgnoresHitTest");
    if (ignoreKey && [*ignoreKey isKindOfClass:NSString.class]) options[*ignoreKey] = @YES;
    id context = ((id (*)(id,SEL,id))objc_msgSend)(cls, sel_registerName("remoteContextWithOptions:"), options);
    if (!ContextID(context) || !Matches(context, "setLayer:", "v24@0:8@16") || !Matches(context, "invalidate", "v16@0:8")) {
        Event(@"REJECT context-instance-abi"); return NO;
    }
    outputContext = context; outputPlayer = player; outputItem = player.currentItem;
    sourceLayer = layer; sourceView = view; sourceBackend = backend; sawBackground = NO;
    automatic = [command[@"automaticDashboard"] boolValue]; exportStarted = CACurrentMediaTime();
    lastTimeControl = player.timeControlStatus;
    token = [command[@"issuedAt"] doubleValue]; expires = [command[@"expires"] doubleValue];
    YTAVEnableStreamVideo(backend, expires);
    previousPolicy = player.audiovisualBackgroundPlaybackPolicy;
    wantsContinue = [command[@"continueIfPossible"] boolValue];
    wantsBackgroundVideo = [command[@"allowBackgroundVideo"] boolValue];
    policyChanged = wantsContinue;
    missingSourceSince = 0;
    if (policyChanged) player.audiovisualBackgroundPlaybackPolicy = AVPlayerAudiovisualBackgroundPlaybackPolicyContinuesIfPossible;
    if (wantsBackgroundVideo && InstallBackgroundExport(player))
        objc_setAssociatedObject(player, &backgroundExportKey, @(expires), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    outputRoot = [CALayer layer]; outputRoot.bounds = CGRectMake(0, 0, 960, 540);
    outputRoot.anchorPoint = CGPointZero; outputRoot.position = CGPointZero;
    outputRoot.backgroundColor = UIColor.blackColor.CGColor;
    if (!YTAV_RELEASE) { outputRoot.borderWidth = 2; outputRoot.borderColor = UIColor.cyanColor.CGColor; }
    pausedFrame = [YTAVPausedFrame new]; pausedFrame.layer.frame = outputRoot.bounds;
    [pausedFrame captureFromLayer:layer];
    outputLayer = [AVPlayerLayer playerLayerWithPlayer:player]; outputLayer.frame = outputRoot.bounds;
    outputLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [outputRoot addSublayer:outputLayer];
    [outputRoot addSublayer:pausedFrame.layer];
    ((void (*)(id,SEL,id))objc_msgSend)(context, sel_registerName("setLayer:"), outputRoot);
    // A local host keeps the in-app picture observable before the background test.
    CALayer *localHost = [NSClassFromString(@"CALayerHost") layer];
    if (!automatic && Matches(localHost, "setContextId:", "v20@0:8I16") && layer.superlayer) {
        preview = [CALayer layer]; preview.frame = layer.frame; preview.masksToBounds = YES;
        CGFloat scale = MIN(preview.bounds.size.width / 960, preview.bounds.size.height / 540);
        localHost.anchorPoint = CGPointZero; localHost.bounds = outputRoot.bounds;
        localHost.position = CGPointMake((preview.bounds.size.width - 960*scale)/2, (preview.bounds.size.height - 540*scale)/2);
        localHost.transform = CATransform3DMakeScale(scale, scale, 1);
        ((void (*)(id,SEL,unsigned))objc_msgSend)(localHost, sel_registerName("setContextId:"), ContextID(context));
        [preview addSublayer:localHost]; [layer.superlayer addSublayer:preview];
    }
    [CATransaction flush];
    if (automatic) {
        uint64_t deadline = YTAV_OWNER_LIFETIME;
        if (!YTAV_RELEASE) {
            double remaining = expires-NSDate.date.timeIntervalSince1970;
            if (remaining <= 0 || remaining > 1800) { YTAVStopDedicatedOutput(@"channel-publish-failed"); return NO; }
            deadline = YTAVChannelMillis() + (uint64_t)(remaining*1000);
        }
        if (!YTAVChannelPublish(&channel, ContextID(context), deadline)) {
            YTAVStopDedicatedOutput(@"channel-publish-failed"); return NO;
        }
    }
    Event([NSString stringWithFormat:@"BEGIN context=%u player=%p item=%p original=%p newLayer=%p policyChanged=%d previousPolicy=%ld",
        ContextID(context), player, player.currentItem, layer, outputLayer, policyChanged, (long)previousPolicy]);
    return YES;
}

static void PrepareAutomatic(void) {
    NSDictionary *command = Command(); BOOL hostVisible;
    if (outputContext || ![command[@"automaticDashboard"] boolValue] ||
        !YTAVChannelHost(&channel, &hostVisible) || CACurrentMediaTime()-candidateStamp > 2 ||
        !candidatePlayer || candidatePlayer.currentItem != candidateItem || candidateLayer.player != candidatePlayer ||
        candidatePlayer.currentItem.status != AVPlayerItemStatusReadyToPlay || !candidateView.window) return;
    Begin(candidateBackend, candidatePlayer, candidateLayer, candidateView, command);
}
static void InstallLifecycle(void) {
    if (lifecycleObservers) return;
    NSMutableArray *observers = [NSMutableArray new];
    for (NSString *name in @[ UISceneWillDeactivateNotification, UIApplicationWillResignActiveNotification ]) {
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if ([note.object isKindOfClass:UIScene.class] && note.object != candidateView.window.windowScene) return;
            @try { PrepareAutomatic(); } @catch (NSException *e) { Event([@"LIFECYCLE " stringByAppendingString:e.name]); YTAVStopDedicatedOutput(@"lifecycle-exception"); }
        }];
        [observers addObject:observer];
    }
    // Scene activation precedes app activation. The tick returns presentation only
    // after both are active, so AVFoundation no longer treats the player as background.
    lifecycleObservers = observers;
}
void YTAVSelectedOutputBackendChanged(id previous, id selected) {
    if (!NSThread.isMainThread || !outputContext || !automatic || !previous ||
        (previous != sourceBackend && previous != pendingBackend) || NSDate.date.timeIntervalSince1970 >= expires) return;
    if (pendingBackend && pendingBackend != sourceBackend) YTAVDisableStreamVideo(pendingBackend);
    pendingBackend = [selected isKindOfClass:NSClassFromString(@"MLAVPlayer")] ? selected : nil;
    if (pendingBackend) YTAVEnableStreamVideo(pendingBackend, expires);
}
void YTAVObserveDedicatedOutput(id backend, AVPlayer *player, AVPlayerLayer *layer, UIView *view, BOOL activeInPool) {
    if (![NSThread isMainThread] || !activeInPool || ![player isKindOfClass:AVPlayer.class]) return;
    // Pool ownership distinguishes the selected item from preloaded or retired players.
    if (selectedBackend != backend || selectedPlayer != player) selectedCount++;
    selectedBackend = backend; selectedPlayer = player;
    selectedLayer = [layer isKindOfClass:AVPlayerLayer.class] ? layer : nil;
    selectedView = [view isKindOfClass:UIView.class] ? view : nil;
    if (!selectedLayer || !selectedView || layer.player != player ||
        player.currentItem.status != AVPlayerItemStatusReadyToPlay || !VisibleSource(view)) return;
    if (observedPlayer != player) observedCount++;
    observedBackend = backend; observedPlayer = player; observedLayer = layer; observedView = view;
}
void YTAVTickDedicatedOutput(void) {
    if (![NSThread isMainThread]) return;
    @try {
        InstallLifecycle();
        if (observedCount == 1) {
            candidateBackend = observedBackend; candidatePlayer = observedPlayer;
            candidateLayer = observedLayer; candidateView = observedView; candidateItem = observedPlayer.currentItem;
            candidateStamp = CACurrentMediaTime();
        } else if (observedCount > 1) {
            candidateBackend = nil; candidatePlayer = nil; candidateLayer = nil; candidateView = nil; candidateItem = nil;
        }
        NSDictionary *command = Command();
        double now = NSDate.date.timeIntervalSince1970;
        double issued = [command[@"issuedAt"] doubleValue];
        if (!command) { YTAVStopDedicatedOutput(@"command-ended"); return; }
        if (outputContext) {
            if (now >= expires) { YTAVStopDedicatedOutput(@"frozen-deadline"); return; }
            if (selectedCount > 1) { YTAVStopDedicatedOutput(@"ambiguous-selection"); return; }
            if (selectedCount == 1 && selectedPlayer.currentItem && selectedPlayer.currentItem.status != AVPlayerItemStatusFailed &&
                selectedLayer && selectedView && (!selectedLayer.player || selectedLayer.player == selectedPlayer)) {
                if (selectedPlayer != outputPlayer || selectedPlayer.currentItem != outputItem)
                    AdoptPlayer(selectedBackend, selectedPlayer, selectedLayer, selectedView);
                else { sourceBackend = selectedBackend; sourceLayer = selectedLayer; sourceView = selectedView; }
                missingSourceSince = 0;
            } else {
                // Player creation and item replacement can briefly leave no current source.
                // Keep the context during that transition, without extending its deadline.
                if (!missingSourceSince) missingSourceSince = CACurrentMediaTime();
                if (CACurrentMediaTime()-missingSourceSince > 8) { YTAVStopDedicatedOutput(@"selection-unavailable"); return; }
            }
            UISceneActivationState scene = sourceView.window.windowScene.activationState;
            BOOL background = UIApplication.sharedApplication.applicationState == UIApplicationStateBackground ||
                (sourceView.window.windowScene && scene == UISceneActivationStateBackground);
            if (background && !sawBackground) {
                sawBackground = YES;
                Event([NSString stringWithFormat:@"BACKGROUND_REFRESH observers=%@ state=%@",
                    YTAVRefreshPlaybackObservers(sourceBackend, outputPlayer), YTAVPlaybackState(sourceBackend, outputPlayer)]);
            }
            else if (sawBackground && UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
                sourceView.window.windowScene && scene == UISceneActivationStateForegroundActive) {
                YTAVStopDedicatedOutput(@"natural-return"); return;
            }
            if (automatic && background && CACurrentMediaTime()-exportStarted > 3) {
                BOOL visible = NO;
                if (!YTAVChannelHost(&channel, &visible) || !visible) { YTAVStopDedicatedOutput(@"dashboard-left"); return; }
            }
            double clock = outputPlayer.currentItem.timebase ? CMTimebaseGetRate(outputPlayer.currentItem.timebase) : 0;
            if (outputPlayer.timeControlStatus != lastTimeControl ||
                (clock > .01 && outputPlayer.rate == 0 && outputPlayer.timeControlStatus == AVPlayerTimeControlStatusPlaying)) {
                Event([NSString stringWithFormat:@"CONTROL_REFRESH %@", YTAVRefreshPlaybackObservers(sourceBackend, outputPlayer)]);
                lastTimeControl = outputPlayer.timeControlStatus;
            }
            [pausedFrame updateFromLayer:outputLayer mediaTime:CMTimeGetSeconds(outputPlayer.currentTime)];
            if (preview && sourceLayer.superlayer) preview.frame = sourceLayer.frame;
            if (CACurrentMediaTime()-lastStateWrite >= .95) { WriteState(@"active"); lastStateWrite = CACurrentMediaTime(); }
            return;
        }
        if ([command[@"automaticDashboard"] boolValue] || issued <= highestToken || observedCount != 1) return;
        highestToken = issued;
        if (Begin(candidateBackend, candidatePlayer, candidateLayer, candidateView, command)) WriteState(@"active");
    } @catch (NSException *exception) {
        Event([@"EXCEPTION " stringByAppendingString:exception.name]); YTAVStopDedicatedOutput(@"exception");
    } @finally {
        observedCount = 0; observedBackend = nil; observedPlayer = nil; observedLayer = nil; observedView = nil;
        selectedCount = 0; selectedBackend = nil; selectedPlayer = nil; selectedLayer = nil; selectedView = nil;
    }
}
void YTAVShutdownDedicatedOutput(void) {
    YTAVStopDedicatedOutput(@"sampler-stop");
    for (id observer in lifecycleObservers) [NSNotificationCenter.defaultCenter removeObserver:observer];
    lifecycleObservers = nil;
    YTAVChannelWithdraw(&channel); YTAVChannelClose(&channel);
    candidateBackend = nil; candidatePlayer = nil; candidateLayer = nil; candidateView = nil; candidateItem = nil;
}
