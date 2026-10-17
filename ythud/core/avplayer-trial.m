#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <unistd.h>
#import "dedicated-output.h"
#import "mini-player-layout.h"
#import "runtime-mode.h"

@interface MLAVPlayer : NSObject
- (instancetype)initWithVideo:(id)video playerConfig:(id)config stickySettings:(id)sticky
    externalPlaybackActive:(BOOL)external mediaPlayerResources:(id)resources;
@end

static NSString *CommandPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"ytav-command.plist"];
}
static NSHashTable *players, *pools;
static NSMutableDictionary *lastTimes;
static NSFileHandle *logFile;
static NSTimeInterval started;
static NSTimeInterval lastSampleLog;
static char forcedConfigKey;
typedef id (*AcquireIMP)(id, SEL, id, id, id, id, id, id, id);
static AcquireIMP originalAcquire;
static BOOL (*originalCanQueue)(id, SEL, id, id, id, id *);
static id (*originalView)(id, SEL, id, id, id);
static BOOL (*originalCanUse)(id, SEL, id, id);
static void (*originalSetActive)(id, SEL, id, id);

static void Log(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
static void Log(NSString *format, ...) {
    if (YTAV_RELEASE) return;
    @synchronized (logFile) {
        if (!logFile || logFile.offsetInFile > 2 * 1024 * 1024) return;
        va_list args; va_start(args, format);
        NSString *body = [[NSString alloc] initWithFormat:format arguments:args]; va_end(args);
        NSString *line = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, body];
        [logFile writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

static BOOL Signature(Class cls, const char *name, const char *types) {
    Method m = class_getInstanceMethod(cls, sel_registerName(name));
    return m && strcmp(method_getTypeEncoding(m), types) == 0;
}

static id Get(id object, const char *name) {
    if (!object) return nil;
    Method m = class_getInstanceMethod(object_getClass(object), sel_registerName(name));
    if (!m || method_getNumberOfArguments(m) != 2) return nil;
    char type[32]; method_getReturnType(m, type, sizeof(type));
    if (type[0] != '@') return nil;
    return ((id (*)(id,SEL))objc_msgSend)(object, sel_registerName(name));
}

static id ObjectIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
    return ivar && ivar_getTypeEncoding(ivar)[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static BOOL Enabled(void) {
    if (YTAV_RELEASE) return YES;
    NSDictionary *command = [NSDictionary dictionaryWithContentsOfFile:CommandPath()];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    double issued = [command[@"issuedAt"] doubleValue], expires = [command[@"expires"] doubleValue];
    return [command[@"enabled"] boolValue] && issued <= now && now < expires && expires - issued <= 1800;
}

static BOOL ForceVideo(id video) {
    if (YTAV_RELEASE) return YES;
    if (!Enabled()) return NO;
    NSDictionary *command = [NSDictionary dictionaryWithContentsOfFile:CommandPath()];
    id streaming = Get(video, "streamingData");
    BOOL hls = NO;
    if (Signature(object_getClass(streaming), "hasHLSData", "B16@0:8"))
        hls = ((BOOL (*)(id,SEL))objc_msgSend)(streaming, sel_registerName("hasHLSData"));
    return hls || [command[@"forceWithoutHLS"] boolValue];
}

static id Acquire(id self, SEL cmd, id video, id config, id sticky, id latency, id reload, id resources, id recomposite) {
    @synchronized (pools) { [pools addObject:self]; }
    id streams = Get(video, "streamingData");
    NSArray *hls = Get(streams, "HLSStreams"), *clear = Get(streams, "clearNonAdaptiveStreams"), *adaptive = Get(streams, "adaptiveStreams");
    BOOL force = ForceVideo(video);
    Log(@"ACQUIRE video=%@ hls=%lu clear=%lu adaptive=%lu force=%d", Get(video, "ID"),
        (unsigned long)hls.count, (unsigned long)clear.count, (unsigned long)adaptive.count, force);
    if (!force) return originalAcquire(self, cmd, video, config, sticky, latency, reload, resources, recomposite);
    id active = ObjectIvar(self, "_activePlayer");
    BOOL external = NO;
    if (Signature(object_getClass(active), "externalPlaybackActive", "B16@0:8"))
        external = ((BOOL (*)(id,SEL))objc_msgSend)(active, sel_registerName("externalPlaybackActive"));
    MLAVPlayer *player = [(MLAVPlayer *)[NSClassFromString(@"MLAVPlayer") alloc]
        initWithVideo:video playerConfig:config stickySettings:sticky externalPlaybackActive:external mediaPlayerResources:resources];
    if (!player) {
        Log(@"FALLBACK reason=nil-player");
        return originalAcquire(self, cmd, video, config, sticky, latency, reload, resources, recomposite);
    }
    if (Signature(object_getClass(sticky), "rate", "f16@0:8")) {
        float rate = ((float (*)(id,SEL))objc_msgSend)(sticky, sel_registerName("rate"));
        ((void (*)(id,SEL,float))objc_msgSend)(player, sel_registerName("setRate:"), rate);
    }
    objc_setAssociatedObject(config, &forcedConfigKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @synchronized (players) { [players addObject:player]; }
    Log(@"FORCED player=%p class=%@ video=%@", player, NSStringFromClass(object_getClass(player)), Get(video, "ID"));
    return player;
}

static void SetActive(id self, SEL cmd, id player, id resources) {
    id previous = ObjectIvar(self, "_activePlayer");
    originalSetActive(self, cmd, player, resources);
    YTAVSelectedOutputBackendChanged(previous, player);
    @synchronized (pools) { [pools addObject:self]; }
    Log(@"ACTIVE pool=%p backend=%p class=%@", self, player, NSStringFromClass(object_getClass(player)));
}

static BOOL CanQueue(id self, SEL cmd, id video, id config, id reload, id *error) {
    BOOL force = ForceVideo(video);
    Log(@"QUEUE_CHECK video=%@ force=%d", Get(video, "ID"), force);
    return force ? NO : originalCanQueue(self, cmd, video, config, reload, error);
}

static id PlayerView(id self, SEL cmd, id video, id config, id resources) {
    // A failed native-player allocation must keep its original rendering path.
    if (![objc_getAssociatedObject(config, &forcedConfigKey) boolValue])
        return originalView(self, cmd, video, config, resources);
    id factory = ObjectIvar(self, "_playerViewFactory");
    if (!Signature(object_getClass(factory), "AVPlayerViewForPlayerConfig:", "@24@0:8@16")) {
        Log(@"VIEW_FALLBACK reason=factory-abi");
        return originalView(self, cmd, video, config, resources);
    }
    id view = ((id (*)(id,SEL,id))objc_msgSend)(factory, sel_registerName("AVPlayerViewForPlayerConfig:"), config);
    if (Signature(object_getClass(view), "setVideo:playerConfig:", "v32@0:8@16@24"))
        ((void (*)(id,SEL,id,id))objc_msgSend)(view, sel_registerName("setVideo:playerConfig:"), video, config);
    Log(@"VIEW view=%p class=%@", view, NSStringFromClass(object_getClass(view)));
    return view;
}

static BOOL CanUse(id self, SEL cmd, id view, id config) {
    if (objc_getAssociatedObject(config, &forcedConfigKey))
        return [view isKindOfClass:NSClassFromString(@"MLAVPlayerLayerView")] ||
               [view isKindOfClass:NSClassFromString(@"MLAVPIPPlayerLayerView")];
    return originalCanUse(self, cmd, view, config);
}

static void Sample(void) {
    @autoreleasepool {
        double now = NSDate.date.timeIntervalSince1970;
        BOOL record = !YTAV_RELEASE && now-lastSampleLog >= .95;
        if (record) lastSampleLog = now;
        NSArray *snapshot, *poolSnapshot;
        @synchronized (players) { snapshot = players.allObjects; }
        @synchronized (pools) { poolSnapshot = pools.allObjects; }
        NSHashTable *activePlayers = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
        for (id pool in poolSnapshot) {
            id active = ObjectIvar(pool, "_activePlayer");
            if (active) [activePlayers addObject:active];
        }
        for (id backend in snapshot) {
            AVPlayer *player = ObjectIvar(backend, "_player");
            id assetPlayer = Get(backend, "assetPlayer");
            if (![player isKindOfClass:AVPlayer.class]) player = ObjectIvar(assetPlayer, "_player");
            AVPlayerItem *item = [player isKindOfClass:AVPlayer.class] ? player.currentItem : nil;
            id view = Get(backend, "renderingView");
            AVPlayerLayer *layer = Get(view, "playerLayer");
            YTAVObserveDedicatedOutput(backend, player, layer, view, [activePlayers containsObject:backend]);
            if (!record) continue;
            double time = item ? CMTimeGetSeconds(item.currentTime) : NAN;
            NSNumber *key = @((uintptr_t)(__bridge void *)backend);
            NSNumber *previous = lastTimes[key];
            if (isfinite(time)) lastTimes[key] = @(time);
            NSMutableArray *trackTypes = [NSMutableArray array];
            for (AVPlayerItemTrack *track in item.tracks)
                [trackTypes addObject:[NSString stringWithFormat:@"%@:%d", track.assetTrack.mediaType, track.enabled]];
            id selector = Get(backend, "streamSelector"), format = Get(backend, "selectedVideoFormat");
            Log(@"FORMAT backend=%p selector=%@ videoFormat=%p videoFormats=%lu constraint=%@ viewport=%@ visible=%d",
                backend, NSStringFromClass(object_getClass(selector)), format,
                (unsigned long)[Get(backend, "selectableVideoFormats") count],
                NSStringFromClass(object_getClass(Get(backend, "videoFormatConstraint"))),
                NSStringFromClass(object_getClass(ObjectIvar(backend, "_viewportSizeProvider"))),
                Signature(object_getClass(backend), "isVisible", "B16@0:8") ? ((BOOL (*)(id,SEL))objc_msgSend)(backend, sel_registerName("isVisible")) : -1);
            Log(@"SAMPLE backend=%p avplayer=%p item=%p status=%ld time=%.3f delta=%.3f rate=%.2f muted=%d volume=%.2f view=%@ window=%p layer=%p ready=%d activeInPool=%d tracks=%@ error=%@/%ld",
                backend, player, item, (long)item.status, time, previous ? time - previous.doubleValue : NAN,
                player.rate, player.muted, player.volume, NSStringFromClass(object_getClass(view)),
                [view isKindOfClass:UIView.class] ? [(UIView *)view window] : nil, layer,
                [layer isKindOfClass:AVPlayerLayer.class] && layer.readyForDisplay, [activePlayers containsObject:backend],
                trackTypes, item.error.domain, (long)item.error.code);
        }
        YTAVTickDedicatedOutput();
    }
}

static void Install(void) {
    Class pool = NSClassFromString(@"MLPlayerPoolImpl"), native = NSClassFromString(@"MLAVPlayer");
    const char *acquire = "acquirePlayerForVideo:playerConfig:stickySettings:latencyLogger:reloadContext:mediaPlayerResources:recompositeProvider:";
    const char *queue = "canQueuePlayerPlayVideo:playerConfig:reloadContext:error:";
    const char *view = "playerViewForVideo:playerConfig:mediaPlayerResources:";
    const char *reuse = "canUsePlayerView:forPlayerConfig:";
    const char *setActive = "setActivePlayer:mediaPlayerResources:";
    if (!Signature(NSClassFromString(@"MLDefaultPlayerViewFactory"), "AVPlayerViewForPlayerConfig:", "@24@0:8@16") ||
        !Signature(pool, acquire, "@72@0:8@16@24@32@40@48@56@64") ||
        !Signature(pool, queue, "B48@0:8@16@24@32^@40") ||
        !Signature(pool, view, "@40@0:8@16@24@32") || !Signature(pool, reuse, "B32@0:8@16@24") ||
        !Signature(pool, setActive, "v32@0:8@16@24") ||
        !Signature(native, "initWithVideo:playerConfig:stickySettings:externalPlaybackActive:mediaPlayerResources:", "@52@0:8@16@24@32B40@44") ||
        !Signature(native, "setRate:", "v20@0:8f16")) { Log(@"SKIP reason=abi-mismatch"); return; }
    Method acquireMethod = class_getInstanceMethod(pool, sel_registerName(acquire));
    Method queueMethod = class_getInstanceMethod(pool, sel_registerName(queue));
    Method viewMethod = class_getInstanceMethod(pool, sel_registerName(view));
    Method reuseMethod = class_getInstanceMethod(pool, sel_registerName(reuse));
    Method activeMethod = class_getInstanceMethod(pool, sel_registerName(setActive));
    originalSetActive = (void *)method_getImplementation(activeMethod);
    originalAcquire = (AcquireIMP)method_getImplementation(acquireMethod);
    originalCanQueue = (void *)method_getImplementation(queueMethod);
    originalView = (void *)method_getImplementation(viewMethod);
    originalCanUse = (void *)method_getImplementation(reuseMethod);
    method_setImplementation(activeMethod, (IMP)SetActive);
    method_setImplementation(acquireMethod, (IMP)Acquire);
    method_setImplementation(queueMethod, (IMP)CanQueue);
    method_setImplementation(viewMethod, (IMP)PlayerView);
    method_setImplementation(reuseMethod, (IMP)CanUse);
    YTAVInstallMiniPlayerLayout(Enabled);
    Log(@"INSTALLED version=%@ guarded=1", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    __block NSTimer *timer;
    timer = [NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(__unused NSTimer *t) {
        if (!YTAV_RELEASE) {
            NSString *stop = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ytav-trial-stop"];
            if (NSDate.date.timeIntervalSince1970 - started > 1800 || [NSFileManager.defaultManager fileExistsAtPath:stop]) {
                YTAVShutdownDedicatedOutput();
                [timer invalidate]; timer = nil; Log(@"STOP"); return;
            }
        }
        Sample();
    }];
}

__attribute__((constructor)) static void BeginTrial(void) {
    @autoreleasepool {
        started = NSDate.date.timeIntervalSince1970;
        players = [NSHashTable weakObjectsHashTable]; pools = [NSHashTable weakObjectsHashTable]; lastTimes = [NSMutableDictionary dictionary];
        if (!YTAV_RELEASE) {
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ytav-trial.log"];
            [NSData.data writeToFile:path atomically:YES];
            logFile = [NSFileHandle fileHandleForWritingAtPath:path];
        }
        Log(@"BEGIN pid=%d", getpid());
        // The shared queue player is created during app startup. Hook before
        // application launch; a delayed install misses that initial selection.
        if (NSClassFromString(@"MLPlayerPoolImpl")) Install();
        else dispatch_async(dispatch_get_main_queue(), ^{ Install(); });
    }
}
