#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <notify.h>
#import "nav-source.h"
#import "diagnostics.h"
#import "background-location.h"
#ifdef VM_GOOGLE_MAPS_RELAY
#import "speed-state.h"
#import "source-transport.h"
#import "vietmap-output.h"
#import "vietmap-alert-assets.h"
static int requestToken=-1;
static NSTimeInterval lastRequestHandled=-1;
static BOOL forceOutput;
static NSArray<NSDictionary *> *upcomingAlerts, *stickyAlerts;
static NSTimeInterval upcomingReceived, stickyReceived;
// The lanes VietMap Live shows (its overlay's laneInfo): in effect on the stretch being driven, kept
// until VietMap changes or clears them. Its advance countdown (updateLaneInfo) shows the next
// junction's lanes earlier, with their distance, while it runs.
static NSArray<NSNumber *> *laneCodes, *laneLimits;
static NSTimeInterval laneCodesReceived=-1, laneLimitsReceived=-1;
static NSDictionary *advanceLanes;
static NSTimeInterval advanceReceived=-1;
#endif

@protocol VMFlutterMethodCall
- (NSString *)method;
- (id)arguments;
@end

typedef void (^VMFlutterResult)(id result);
typedef void (^VMFlutterHandler)(id<VMFlutterMethodCall> call, VMFlutterResult result);
static VMNavSource *source;
static dispatch_source_t heartbeat;
static BOOL hookInstalled;
static Ivar channelNameIvar;
static void (*originalSetHandler)(id, SEL, VMFlutterHandler);

// Diagnostics stay inside the app sandbox and contain no location or route data.
static void BridgeLog(NSString *message) {
#ifdef VM_GOOGLE_MAPS_RELAY
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"googlemaps-vietmap-source.log"];
#else
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"truedash-vietmap.log"];
#endif
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize] > 65536) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [file seekToEndOfFile];
        [file writeData:[[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message]
            dataUsingEncoding:NSUTF8StringEncoding]];
        [file closeFile];
    } @catch (__unused NSException *exception) {}
}

static void Publish(void) {
#ifdef VM_GOOGLE_MAPS_RELAY
    GVMRefreshLocationSession();
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSMutableDictionary *samples=[[source freshSamplesAtUptime:now] mutableCopy] ?: [NSMutableDictionary new];
    GVMDiagnosticsRecord(GVMDiagnosticSamples,(samples[@"speed"] ? 1 : 0) | (samples[@"speedLimit"] ? 2 : 0) | (UIApplication.sharedApplication.applicationState==UIApplicationStateActive ? 4 : 0));
    if (GVMSelectedSourceID()!=GVMSourceVietMap) return;
    BOOL counting=advanceLanes && now-advanceReceived<GVMVietMapAdvanceLaneLifetime;
    NSDictionary *lanes=GVMVietMapLaneSample(counting ? advanceLanes : nil,laneCodes,laneLimits,now);
    if (lanes) samples[@"lanes"]=lanes;
    NSMutableArray *entries=[NSMutableArray new];
    for (NSDictionary *alert in upcomingAlerts)
        [entries addObject:@{@"sample":alert,@"receivedAt":@(upcomingReceived)}];
    for (NSDictionary *alert in stickyAlerts)
        [entries addObject:@{@"sample":alert,@"receivedAt":@(stickyReceived),@"active":@YES}];
    NSDictionary *output=GVMVietMapOutput(samples,entries,now);
    if (GVMPublishSourceOutput(output,now,forceOutput)) forceOutput=NO;
    else { BridgeLog(@"common source output publication refused"); GVMDiagnosticsRecord(GVMDiagnosticError,1); }

#else
    NSDictionary *payload = [source payloadAtUptime:NSProcessInfo.processInfo.systemUptime
        timestamp:NSDate.date.timeIntervalSince1970];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"truedash_navprovider.plist"];
    if ([payload writeToFile:path atomically:YES]) notify_post("com.sensetechlab.navprovider.update");
    else BridgeLog(@"publish failed");
#endif
}

#ifdef VM_GOOGLE_MAPS_RELAY
// While observing, keep a copy of each image VietMap registers for its CarPlay views (its own
// lane and maneuver icons), named by key, so the keys used in laneInfo can be matched to icons.
static NSUInteger SaveNavigationImages(id payload,NSString *path,NSUInteger saved) {
    if (saved>=32) return saved;
    NSData *data=GVMVietMapDataValue(payload);
    if (data) {
        if (data.length>131072) return saved;
        NSCharacterSet *unsafe=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"] invertedSet];
        NSString *name=[[path componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
        name=[name substringToIndex:MIN(name.length,48)];
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"gmaphud-navimage-%@.png",name.length ? name : @"value"]] atomically:YES];
        return saved+1;
    }
    if ([payload isKindOfClass:NSDictionary.class])
        for (id key in [[(NSDictionary *)payload allKeys] sortedArrayUsingSelector:@selector(compare:)])
            if ([key isKindOfClass:NSString.class]) saved=SaveNavigationImages(payload[key],[path stringByAppendingFormat:@"%@%@",path.length ? @"." : @"",key],saved);
    if ([payload isKindOfClass:NSArray.class])
        for (NSUInteger i=0;i<MIN([payload count],32);i++) saved=SaveNavigationImages(payload[i],[path stringByAppendingFormat:@"%@%lu",path.length ? @"." : @"",(unsigned long)i],saved);
    return saved;
}
static void ObserveAlerts(NSString *method,id payload,NSUInteger accepted,NSTimeInterval received) {
    NSString *gate=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-alert-observation.enable"];
    NSDate *modified=[[NSFileManager.defaultManager attributesOfItemAtPath:gate error:nil] fileModificationDate];
    NSTimeInterval age=modified ? -modified.timeIntervalSinceNow : -1;
    if (age<0 || age>180) return;
    static NSMutableDictionary *last;
    @synchronized(source) {
        if (!last) last=[NSMutableDictionary new];
        // Image registrations come in bursts and each one matters; repeated status updates are sampled.
        BOOL burst=[method isEqualToString:@"setNavigationImage"] || [method isEqualToString:@"cacheImage"] ||
            ([method isEqualToString:@"updateMapOverlayData"] && GVMVietMapOverlayCarriesImages(payload));
        if (!burst && last[method] && received-[last[method] doubleValue]<2) return;
        last[method]=@(received);
    }
    // Capture one explicitly selected warning image locally, never its payload or coordinates.
    if ([method isEqualToString:@"updateStickyAlerts"] && [payload isKindOfClass:NSArray.class]) {
        NSString *imageGate=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-alert-image.enable"];
        NSDate *imageModified=[[NSFileManager.defaultManager attributesOfItemAtPath:imageGate error:nil] fileModificationDate];
        if (imageModified && -imageModified.timeIntervalSinceNow>=0 && -imageModified.timeIntervalSinceNow<=180) {
            for (__strong id item in [payload subarrayWithRange:NSMakeRange(0,MIN([payload count],8))]) {
                if ([item isKindOfClass:NSString.class] && [item length]<=262144)
                    item=[NSJSONSerialization JSONObjectWithData:[item dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                id encoded=[item isKindOfClass:NSDictionary.class] ? item[@"image"] : nil;
                if (![encoded isKindOfClass:NSString.class] || [encoded length]>180000) continue;
                NSData *bytes=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
                NSDictionary *observed=GVMVietMapAlertObservation(@[item],0);
                NSString *hash=[observed[@"items"] firstObject][@"imageSHA256"];
                if (![hash isEqualToString:@"ee9fc9ee37a92ddfa0d9090d7add3172efdced4efa3ac1cc0bf90c310faf1881"] ||
                    !bytes.length || bytes.length>131072) continue;
                NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-alert-image.png"];
                if ([bytes writeToFile:path options:NSDataWritingAtomic error:nil])
                    [NSFileManager.defaultManager removeItemAtPath:imageGate error:nil];
                break;
            }
        }
    }
    BOOL value=[@[@"updateLaneInfo",@"setNavigationImage",@"cacheImage"] containsObject:method];
    NSDictionary *summary=[method isEqualToString:@"updateMapOverlayData"] ? GVMVietMapOverlayObservation(payload) :
        value ? GVMVietMapValueObservation(payload) : GVMVietMapAlertObservation(payload,accepted);
    if ([method isEqualToString:@"setNavigationImage"]) SaveNavigationImages(payload,@"",0);
    if ([method isEqualToString:@"updateMapOverlayData"] && GVMVietMapOverlayCarriesImages(payload)) {
        NSUInteger saved=0;
        NSDictionary *patch=GVMVietMapOverlayPatch(payload);
        for (NSString *key in patch) if (GVMVietMapDataValue(patch[key])) saved=SaveNavigationImages(patch[key],key,saved);
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:summary options:0 error:nil];
    NSString *json=data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (json) dispatch_async(dispatch_get_main_queue(), ^{
        BridgeLog([NSString stringWithFormat:@"alert-observation method=%@ %@",method,json]);
    });
}
#endif

static void SetMethodCallHandler(id channel, SEL selector, VMFlutterHandler handler) {
    id name = object_getIvar(channel, channelNameIvar);
    if (!handler || ![name isKindOfClass:NSString.class] || (![name isEqualToString:@"vietmap_car_method_channel"] && ![name isEqualToString:@"vml_main_channel"])) {
        originalSetHandler(channel, selector, handler);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ BridgeLog(@"VietMap overlay handler registered"); GVMDiagnosticsRecord(GVMDiagnosticChannel,1); });
    VMFlutterHandler wrapped = ^(id<VMFlutterMethodCall> call, VMFlutterResult result) {
        NSArray *update = nil;
#ifdef VM_GOOGLE_MAPS_RELAY
        NSArray *overlaySticky=nil;
        NSArray<NSNumber *> *overlayLanes=nil, *overlayLimits=nil;
#endif
        id mainLimit=nil, mainSpeed=nil; BOOL hasMainLimit=NO, hasMainSpeed=NO;
        NSTimeInterval received = NSProcessInfo.processInfo.systemUptime;
        @try {
    #ifdef VM_GOOGLE_MAPS_RELAY
            if ([name isEqualToString:@"vml_main_channel"] && ([[call method] isEqualToString:@"updateLaneInfo"] ||
                [[call method] isEqualToString:@"cacheImage"]))
                ObserveAlerts([call method],[call arguments],0,received);
            if ([name isEqualToString:@"vml_main_channel"] && [[call method] isEqualToString:@"updateLaneInfo"]) {
                NSDictionary *ahead=GVMVietMapAdvanceLanes([call arguments]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (received<advanceReceived) return;
                    advanceLanes=ahead.count ? ahead : nil; advanceReceived=received;
                    Publish();
                });
            }
            if ([name isEqualToString:@"vietmap_car_method_channel"] && [[call method] isEqualToString:@"setNavigationImage"])
                ObserveAlerts(@"setNavigationImage",[call arguments],0,received);
            if ([name isEqualToString:@"vml_main_channel"] &&
                ([[call method] isEqualToString:@"updateUpcommingAlerts"] ||
                 [[call method] isEqualToString:@"updateStickyAlerts"])) {
                BOOL sticky=[[call method] isEqualToString:@"updateStickyAlerts"];
                id alertPayload=[call arguments];
                NSArray<NSDictionary *> *alerts=GVMVietMapAlertsFromPayload(alertPayload);
                ObserveAlerts([call method],alertPayload,alerts.count,received);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (sticky && received>=stickyReceived) { stickyAlerts=alerts; stickyReceived=received; }
                    else if (!sticky && received>=upcomingReceived) { upcomingAlerts=alerts; upcomingReceived=received; }
                    Publish();
                });
            }
#endif
            if ([name isEqualToString:@"vml_main_channel"] &&
                ([[call method] isEqualToString:@"updateCurrentSpeed"] || [[call method] isEqualToString:@"updateSpeedLimit"])) {
                id value=[call arguments];
                if ([[call method] isEqualToString:@"updateSpeedLimit"]) {
                    hasMainLimit=YES;
                    mainLimit=[value isKindOfClass:NSNumber.class] ? [value copy] : NSNull.null;
                } else {
                    hasMainSpeed=YES;
                    mainSpeed=[value isKindOfClass:NSNumber.class] ? [value copy] : NSNull.null;
                }
                NSString *method=[[call method] copy];
                BOOL numeric=[value isKindOfClass:NSNumber.class];
                NSString *type=value ? NSStringFromClass([value class]) : @"nil";
                NSString *safeValue=numeric ? [value description] : @"not-numeric";
                dispatch_async(dispatch_get_main_queue(), ^{
                    static NSMutableDictionary *last;
                    if (!last) last=[NSMutableDictionary new];
                    if (!last[method] || received-[last[method] doubleValue]>=2) {
                        last[method]=@(received);
                        BridgeLog([NSString stringWithFormat:@"source-scalar method=%@ type=%@ value=%@",method,type,safeValue]);
                    }
                });
            }
            // Log only bounded method/type metadata; never argument values or coordinates.
            static NSMutableDictionary *methodTimes;
            @synchronized(source) {
                if (!methodTimes) methodTimes=[NSMutableDictionary new];
                NSString *method=[call method];
                if ([method isKindOfClass:NSString.class] && method.length<=80 &&
                    [method rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet]].location==NSNotFound) {
                    NSString *key=[name stringByAppendingFormat:@"/%@",method];
                    if (methodTimes[key] || methodTimes.count<32) {
                        if (!methodTimes[key] || received-[methodTimes[key] doubleValue]>=10) {
                            methodTimes[key]=@(received);
                            id args=[call arguments];
                            NSString *shape=[args isKindOfClass:NSArray.class] ? @"array" : [args isKindOfClass:NSDictionary.class] ? @"dictionary" : [args isKindOfClass:NSString.class] ? @"string" : @"other";
                            NSString *line=[NSString stringWithFormat:@"channel=%@ method=%@ type=%@",name,method,shape];
                            dispatch_async(dispatch_get_main_queue(), ^{ BridgeLog(line); });
                        }
                    }
                }
            }
            if ([name isEqualToString:@"vietmap_car_method_channel"] && [[call method] isEqualToString:@"updateMapOverlayData"])
            {
                #ifdef VM_GOOGLE_MAPS_RELAY
                overlaySticky=GVMVietMapOverlayStickyAlerts([call arguments]);
                overlayLanes=GVMVietMapOverlayLaneCodes([call arguments]);
                overlayLimits=GVMVietMapOverlayLaneSpeedLimits([call arguments]);
                ObserveAlerts(@"updateMapOverlayData",[call arguments],overlaySticky.count,received);
#endif
                update = VMNavCopyOverlayArguments([call arguments]);
                BOOL valid=update!=nil;
                if (valid) {
                    NSUInteger shape=(update[0][@"speed"] ? 1 : 0) | (update[0][@"speedLimit"] ? 2 : 0) | ([update[1] boolValue] ? 4 : 0);
                    dispatch_async(dispatch_get_main_queue(), ^{ GVMDiagnosticsRecord(GVMDiagnosticShape,shape); });
                }
                dispatch_async(dispatch_get_main_queue(), ^{ GVMDiagnosticsRecord(GVMDiagnosticPayload,valid ? 1 : 2); });
            }
        } @catch (__unused NSException *exception) {}
        // Forward every call and its original reply block exactly once.
        handler(call, result);
        if (hasMainLimit) {
            id copiedLimit=mainLimit;
            dispatch_async(dispatch_get_main_queue(), ^{
                [source applyMainSpeedLimit:copiedLimit receivedAt:received];
                Publish();
            });
        }
        if (hasMainSpeed) {
            id copiedSpeed=mainSpeed;
            dispatch_async(dispatch_get_main_queue(), ^{
                [source applyMainSpeed:copiedSpeed receivedAt:received];
                Publish();
            });
        }
        if (!update) return;
        dispatch_async(dispatch_get_main_queue(), ^{
#ifdef VM_GOOGLE_MAPS_RELAY
            if (overlaySticky && received>=stickyReceived) {
                stickyAlerts=overlaySticky; stickyReceived=received;
            }
            if (overlayLanes && received>=laneCodesReceived) { laneCodes=overlayLanes; laneCodesReceived=received; }
            if (overlayLimits && received>=laneLimitsReceived) { laneLimits=overlayLimits; laneLimitsReceived=received; }
#endif
            [source applyArguments:update receivedAt:received];
            static NSTimeInterval lastLog;
            if (received - lastLog >= 5) {
                lastLog = received;
                NSDictionary *current = [source payloadAtUptime:NSProcessInfo.processInfo.systemUptime
                    timestamp:NSDate.date.timeIntervalSince1970];
                BridgeLog([NSString stringWithFormat:@"overlay state=%ld speed=%@ limit=%@",
                    (long)UIApplication.sharedApplication.applicationState, current[@"currentSpeed"], current[@"speedLimit"]]);
            }
            Publish();
        });
    };
    originalSetHandler(channel, selector, wrapped);
}

static void InstallHook(void) {
    if (hookInstalled) return;
    Class target = NSClassFromString(@"FlutterMethodChannel");
    SEL selector = NSSelectorFromString(@"setMethodCallHandler:");
    Method method = class_getInstanceMethod(target, selector);
    Ivar name = class_getInstanceVariable(target, "_name");
    if (!method || !name) { GVMDiagnosticsRecord(GVMDiagnosticHook,2); return; }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, "v") ||
        strcmp([signature getArgumentTypeAtIndex:2], "@?") || ivar_getTypeEncoding(name)[0] != '@') {
        GVMDiagnosticsRecord(GVMDiagnosticHook,3);
        BridgeLog(@"unsupported Flutter channel ABI; provider inactive");
        return;
    }
    channelNameIvar = name;
    MSHookMessageEx(target, selector, (IMP)SetMethodCallHandler, (IMP *)&originalSetHandler);
    hookInstalled = YES;
    GVMDiagnosticsRecord(GVMDiagnosticHook,1);
    BridgeLog(@"overlay hook installed");
}

static void ImageLoaded(const struct mach_header *header, intptr_t slide) {
    // Class realization and hook installation happen outside the loader callback.
    dispatch_async(dispatch_get_main_queue(), ^{ InstallHook(); });
}

%ctor {
    @autoreleasepool {
        GVMDiagnosticsStart(@"vietmap");
        source = [VMNavSource new];
#ifdef VM_GOOGLE_MAPS_RELAY
        notify_register_dispatch(GVMOutputRequestName(GVMSourceVietMap).UTF8String,&requestToken,dispatch_get_main_queue(), ^(__unused int token) {
            if (GVMSelectedSourceID()!=GVMSourceVietMap) return;
            NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
            if (lastRequestHandled>=0 && now-lastRequestHandled<2) return;
            lastRequestHandled=now;
            NSDictionary *samples=[source freshSamplesAtUptime:now];
            GVMDiagnosticsRecord(GVMDiagnosticResponse,(samples[@"speed"] ? 1 : 0)|(samples[@"speedLimit"] ? 2 : 0));
            // Republish only fresh values with original timestamps. No undocumented Flutter calls.
            forceOutput=YES;
            Publish();
        });
#endif
        // Catch channel registration during application launch when Flutter is already loaded.
        InstallHook();
        _dyld_register_func_for_add_image(ImageLoaded);
        dispatch_async(dispatch_get_main_queue(), ^{
#ifdef VM_GOOGLE_MAPS_RELAY
            BridgeLog(@"independent Google Maps source loaded 0.1.0");
#else
            BridgeLog(@"bridge loaded 0.3.1");
#endif
            InstallHook();
            Publish();
            heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                2 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
            dispatch_source_set_event_handler(heartbeat, ^{ Publish(); });
            dispatch_resume(heartbeat);
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { Publish(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillTerminateNotification
                object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
#ifdef VM_GOOGLE_MAPS_RELAY
                    upcomingAlerts=@[]; stickyAlerts=@[]; laneCodes=nil; laneLimits=nil; advanceLanes=nil; forceOutput=YES;
#endif
                    source = [VMNavSource new]; Publish();
                }];
        });
    }
}
