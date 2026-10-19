#import "background-location.h"
#import "background-policy.h"
#import "source-transport.h"
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#include <notify.h>
#include <stdio.h>
#include <unistd.h>

@interface GVMLocationSession : NSObject
@property(nonatomic, weak) CLLocationManager *manager;
// Requested values may be written by an off-main setter while main applies the lease.
@property(atomic) BOOL requestedBackground, requestedPause, requestedIndicator;
@property(nonatomic) BOOL running, forcedRunning, sourceGPS;
#if GVM_GOFA_SOURCE
@property(atomic) CLLocationDistance requestedDistance;
@property(atomic) BOOL distanceApplied;
#endif
@property(atomic) BOOL applied;
@property(nonatomic) NSUInteger callbacks;
@property(nonatomic) double lastLog;
@end
@implementation GVMLocationSession
@end

#if GVM_WAZE_SOURCE
extern BOOL GVMInitializeWazeNavigation(CLLocationManager *authorizedManager);
extern BOOL GVMWazeNavigationInitializing(void);
extern BOOL GVMWazeOwnsNavigation(CLLocationManager *manager);
extern BOOL GVMStopWazeNavigation(CLLocationManager *manager);
extern void GVMWazeTransferNavigation(void);
extern void GVMWazeEndStationaryHold(void);
static void (*originalHeadingStart)(id,SEL);
static void HeadingStart(id manager,SEL selector) {
    // The lease only needs navigation GPS; do not acquire an untracked compass stream.
    if (!GVMWazeNavigationInitializing()) originalHeadingStart(manager,selector);
}
#endif
static NSHashTable<CLLocationManager *> *managers;
static NSMutableSet<NSString *> *delegateClasses;
static int sessionToken=-1;
static id backgroundActivity;
static BOOL creatingActivity, activityAttempted, unavailableLogged;
static NSUInteger activityGeneration;
static NSString *lastActivityDiagnostic;
static const void *sessionKey=&sessionKey;
static void (*originalStart)(id,SEL), (*originalStop)(id,SEL);
static void (*originalBackground)(id,SEL,BOOL), (*originalPause)(id,SEL,BOOL), (*originalIndicator)(id,SEL,BOOL);
static void (*originalDelegate)(id,SEL,id);
#if GVM_GOFA_SOURCE
static void (*originalDistance)(id,SEL,CLLocationDistance);
#endif

static void Record(NSString *message) {
    NSString *path=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-location-session.log"];
    NSFileManager *fm=NSFileManager.defaultManager;
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize]>32768) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file=[NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [file seekToEndOfFile];
        [file writeData:[[NSString stringWithFormat:@"%.3f %@\n",NSProcessInfo.processInfo.systemUptime,message] dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (__unused NSException *exception) {}
    @finally { [file closeFile]; }
}
static BOOL ActivityMethod(id object,SEL selector,const char *result,NSArray<NSString *> *arguments) {
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments!=arguments.count+2 || strcmp(signature.methodReturnType,result)) return NO;
    for (NSUInteger index=0;index<arguments.count;index++)
        if (strcmp([signature getArgumentTypeAtIndex:index+2],arguments[index].UTF8String)) return NO;
    return YES;
}
static NSString *DiagnosticFlag(id diagnostic,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    if (!ActivityMethod(diagnostic,selector,"B",@[])) return @"unknown";
    return ((BOOL (*)(id,SEL))objc_msgSend)(diagnostic,selector) ? @"1" : @"0";
}
static void RefreshBackgroundActivity(BOOL desired) {
    // This session attests actual When In Use activity; it never grants permission.
    if (creatingActivity) return;
    if (!desired) {
        activityAttempted=NO;
        if (!backgroundActivity) return;
        id previous=backgroundActivity; backgroundActivity=nil;
        activityGeneration++; lastActivityDiagnostic=nil;
        ((void (*)(id,SEL))objc_msgSend)(previous,@selector(invalidate));
        Record(@"temporary location activity invalidated");
        return;
    }
    if (backgroundActivity || activityAttempted) return;
    Class activityClass=NSClassFromString(@"CLBackgroundActivitySession");
    SEL plain=NSSelectorFromString(@"backgroundActivitySession");
    SEL observed=NSSelectorFromString(@"backgroundActivitySessionWithQueue:handler:");
    Method end=class_getInstanceMethod(activityClass,@selector(invalidate));
    char result[8]={0};
    if (end) method_getReturnType(end,result,sizeof(result));
    if (!end || method_getNumberOfArguments(end)!=2 || strcmp(result,"v") ||
        !ActivityMethod(activityClass,plain,"@",@[])) {
        if (!unavailableLogged) { Record(@"temporary location activity API unavailable; manager continuation only"); unavailableLogged=YES; }
        activityAttempted=YES; return;
    }
    activityAttempted=YES; creatingActivity=YES;
    NSUInteger generation=++activityGeneration;
    @try {
        if (ActivityMethod(activityClass,observed,"@",@[@"@",@"@?"])) {
            void (^handler)(id)=^(id diagnostic) {
                if (generation!=activityGeneration) return;
                NSString *state=[NSString stringWithFormat:@"activity diagnostic insufficientlyInUse=%@ denied=%@ restricted=%@ servicesDenied=%@ serviceSessionRequired=%@",
                    DiagnosticFlag(diagnostic,@"insufficientlyInUse"),DiagnosticFlag(diagnostic,@"authorizationDenied"),
                    DiagnosticFlag(diagnostic,@"authorizationRestricted"),DiagnosticFlag(diagnostic,@"authorizationDeniedGlobally"),
                    DiagnosticFlag(diagnostic,@"serviceSessionRequired")];
                if (![state isEqual:lastActivityDiagnostic]) { lastActivityDiagnostic=state; Record(state); }
            };
            backgroundActivity=((id (*)(id,SEL,dispatch_queue_t,id))objc_msgSend)(activityClass,observed,dispatch_get_main_queue(),handler);
        } else {
            backgroundActivity=((id (*)(id,SEL))objc_msgSend)(activityClass,plain);
        }
        Record([NSString stringWithFormat:@"temporary location activity created=%d app=%ld; activation requires GPS verification",backgroundActivity!=nil,(long)UIApplication.sharedApplication.applicationState]);
    } @catch (NSException *exception) {
        activityGeneration++;
        Record([@"temporary location activity creation failed: " stringByAppendingString:exception.name]);
    } @finally { creatingActivity=NO; }
}
static GVMLocationSession *Session(CLLocationManager *manager) {
    GVMLocationSession *session=objc_getAssociatedObject(manager,sessionKey);
    if (!session && NSThread.isMainThread) {
        session=[GVMLocationSession new]; session.manager=manager;
        session.requestedBackground=manager.allowsBackgroundLocationUpdates;
        session.requestedPause=manager.pausesLocationUpdatesAutomatically;
        session.requestedIndicator=manager.showsBackgroundLocationIndicator;
#if GVM_GOFA_SOURCE
        session.requestedDistance=manager.distanceFilter;
#endif
        objc_setAssociatedObject(manager,sessionKey,session,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [managers addObject:manager];
    }
    return session;
}
static NSUInteger ManagedSourceID(void) {
#if GVM_GOFA_SOURCE
    return GVMSourceGofa;
#elif GVM_WAZE_SOURCE
    return GVMSourceWaze;
#else
    return GVMSourceVietMap;
#endif
}
static int sourceSessionToken=-1;
static BOOL Active(CLLocationManager *manager) {
    uint64_t state=0,source=0;
    return sessionToken>=0 && sourceSessionToken>=0 &&
        notify_get_state(sessionToken,&state)==NOTIFY_STATUS_OK &&
        notify_get_state(sourceSessionToken,&source)==NOTIFY_STATUS_OK &&
        source==ManagedSourceID() && GVMSelectedSourceID()==source &&
        GVMBackgroundPermissionAllowed(NSProcessInfo.processInfo.systemUptime,state) &&
        GVMBackgroundLocationAuthorized(manager.authorizationStatus) && CLLocationManager.locationServicesEnabled;
}
static void Apply(GVMLocationSession *session,BOOL active) {
    CLLocationManager *manager=session.manager;
    active=active && (session.running || session.forcedRunning);
    if (!manager) return;
#if GVM_GOFA_SOURCE
    BOOL continuous=active && session.sourceGPS;
    if (session.distanceApplied!=continuous) {
        // GOFA may synchronously publish when this property changes; commit before callbacks.
        session.distanceApplied=continuous;
        originalDistance(manager,@selector(setDistanceFilter:),continuous ? kCLDistanceFilterNone : session.requestedDistance);
        Record([NSString stringWithFormat:@"GOFA distance filter lease=%d requested=%.1f",continuous,session.requestedDistance]);
    }
#endif
    if (session.applied==active) return;
    // Commit before the setters so off-main setter hooks and re-entrant refreshes see the lease.
    session.applied=active;
    originalBackground(manager,@selector(setAllowsBackgroundLocationUpdates:),active ? YES : session.requestedBackground);
    originalPause(manager,@selector(setPausesLocationUpdatesAutomatically:),active ? NO : session.requestedPause);
    originalIndicator(manager,@selector(setShowsBackgroundLocationIndicator:),active ? YES : session.requestedIndicator);
    Record([NSString stringWithFormat:@"location configuration active=%d running=%d app=%ld permission=%d distanceFilter=%.1f desiredAccuracy=%.1f background=%d paused=%d",active,session.running,(long)UIApplication.sharedApplication.applicationState,manager.authorizationStatus,manager.distanceFilter,manager.desiredAccuracy,manager.allowsBackgroundLocationUpdates,manager.pausesLocationUpdatesAutomatically]);
}
void GVMRefreshLocationSession(void) {
    if (!NSThread.isMainThread) return;
#if GVM_WAZE_SOURCE
    if (GVMWazeNavigationInitializing()) return;
    for (CLLocationManager *candidate in managers.allObjects) {
        if (UIApplication.sharedApplication.applicationState==UIApplicationStateActive && GVMWazeOwnsNavigation(candidate)) {
            Session(candidate).running=YES; Session(candidate).forcedRunning=NO;
            GVMWazeTransferNavigation();
        }
    }
    for (CLLocationManager *candidate in managers.allObjects) {
        if (Active(candidate)) {
            if (GVMInitializeWazeNavigation(candidate)) Record(@"navigation GPS initialized by selected-source lease");
            break;
        }
    }
#endif
    BOOL desired=NO;
    for (CLLocationManager *manager in managers.allObjects) {
        GVMLocationSession *session=Session(manager);
        BOOL active=Active(manager);
        // A native cold background launch may construct its GPS delegate without starting
        // updates. The explicit wake lease owns only this measured source GPS manager.
        if (active && session.sourceGPS && !session.running && !session.forcedRunning) {
            session.forcedRunning=YES;
            Apply(session,YES);
#if GVM_GOFA_SOURCE
            // As with Waze, establish the authorized activity before cold background GPS.
            RefreshBackgroundActivity(YES);
#endif
            originalStart(manager,@selector(startUpdatingLocation));
            Record(@"selected source GPS started by wake lease");
        } else if (!active && session.forcedRunning) {
            session.forcedRunning=NO;
            if (!session.running) {
#if GVM_WAZE_SOURCE
                GVMWazeEndStationaryHold();
                if (!GVMStopWazeNavigation(manager))
#endif
                originalStop(manager,@selector(stopUpdatingLocation));
            }
            Record(@"wake-owned source GPS released");
        }
        active=active && (session.running || session.forcedRunning);
        desired=desired || active;
        Apply(session,active);
    }
    RefreshBackgroundActivity(desired);
}
static void ObserveDelegate(id delegate) {
    if (!delegate || !NSThread.isMainThread) return;
    Class cls=object_getClass(delegate);
    NSString *name=NSStringFromClass(cls);
    SEL selector=@selector(locationManager:didUpdateLocations:);
    // A class name that does not convert (nil) would end the app when stored or logged.
    if (!name || [delegateClasses containsObject:name]) return;
    Method method=class_getInstanceMethod(cls,selector);
    if (!method) return;
    NSMethodSignature *signature=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments!=4 || strcmp(signature.methodReturnType,"v") ||
        strcmp([signature getArgumentTypeAtIndex:2],"@") || strcmp([signature getArgumentTypeAtIndex:3],"@")) return;
    __block void (*original)(id,SEL,id,id);
    IMP wrapper=imp_implementationWithBlock(^(id self,CLLocationManager *manager,NSArray *locations) {
        // Forward original GPS objects unchanged; only callback age/count are logged.
        CLLocation *location=locations.lastObject;
        if ([location isKindOfClass:CLLocation.class]) {
            double age=-location.timestamp.timeIntervalSinceNow;
            GVMLocationSession *session=objc_getAssociatedObject(manager,sessionKey);
            if (session) {
                @synchronized(session) {
                    session.callbacks++;
                    double now=NSProcessInfo.processInfo.systemUptime;
                    if (session.applied && now-session.lastLog>=10) {
                        session.lastLog=now;
                        NSUInteger count=session.callbacks;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            Record([NSString stringWithFormat:@"gps callback age=%.1f count=%lu app=%ld",age,(unsigned long)count,(long)UIApplication.sharedApplication.applicationState]);
                        });
                    }
                }
            }
        }
        original(self,selector,manager,locations);
    });
    MSHookMessageEx(cls,selector,wrapper,(IMP *)&original);
    [delegateClasses addObject:name];
    Record([@"observing GPS delegate " stringByAppendingString:name]);
}
static void SetDelegate(CLLocationManager *manager,SEL selector,id delegate) {
    ObserveDelegate(delegate);
    originalDelegate(manager,selector,delegate);
    __weak CLLocationManager *weakManager=manager;
    dispatch_async(dispatch_get_main_queue(), ^{
        CLLocationManager *current=weakManager;
        if (!current) return;
#if GVM_GOFA_SOURCE || GVM_WAZE_SOURCE
        NSString *name=NSStringFromClass([current.delegate class]);
#endif
#if GVM_GOFA_SOURCE
        BOOL primary=[name isEqual:@"GOFA.GofaLocationManager"];
#elif GVM_WAZE_SOURCE
        // Waze also creates a significant-change manager; it is not navigation GPS.
        Ivar original=class_getInstanceVariable(object_getClass(current),"_originalDelegate");
        id receiver=original && ivar_getTypeEncoding(original)[0]=='@' ? object_getIvar(current,original) : nil;
        NSString *receiverName=receiver ? NSStringFromClass(object_getClass(receiver)) : @"";
        BOOL primary=[name isEqual:@"WazeLocationManager"] &&
            ([receiverName isEqual:@"LocationManagerRecorder"] || [receiverName isEqual:@"LocationController"]);
#else
        BOOL primary=NO;
#endif
        Session(current).sourceGPS=primary;
        GVMRefreshLocationSession();
    });
}
static void Start(CLLocationManager *manager,SEL selector) {
    if (NSThread.isMainThread) {
        GVMLocationSession *session=Session(manager);
        BOOL newlyRunning=!session.running;
#if GVM_WAZE_SOURCE
        if (GVMWazeNavigationInitializing()) { session.forcedRunning=YES; session.sourceGPS=YES; }
        else
#endif
        { session.running=YES; session.forcedRunning=NO; }
        ObserveDelegate(manager.delegate); Apply(session,Active(manager));
        if (newlyRunning) Record(@"app requested standard GPS start");
    }
#if GVM_WAZE_SOURCE
    // Establish the activity session before asking Core Location for cold background GPS.
    if (GVMWazeNavigationInitializing() && Active(manager)) RefreshBackgroundActivity(YES);
#endif
    originalStart(manager,selector);
    // Resume promptly during launch; foreground transitions also refresh via Publish.
    GVMRefreshLocationSession();
}
static void Stop(CLLocationManager *manager,SEL selector) {
#if GVM_WAZE_SOURCE
    // A held stationary speed belongs to the GPS run that measured it (also Waze's own stops).
    GVMLocationSession *existing=objc_getAssociatedObject(manager,sessionKey);
    if (existing.sourceGPS) GVMWazeEndStationaryHold();
#endif
    if (NSThread.isMainThread) {
        GVMLocationSession *session=Session(manager); session.running=NO; session.forcedRunning=NO;
        Apply(session,NO); Record(@"app requested standard GPS stop; forwarded");
    }
    originalStop(manager,selector);
}
#if GVM_GOFA_SOURCE
static void Distance(CLLocationManager *manager,SEL selector,CLLocationDistance value) {
    // Off-main setters reuse an existing session; only the main thread creates one.
    GVMLocationSession *session=Session(manager);
    session.requestedDistance=value;
    BOOL leased=session.distanceApplied;
    originalDistance(manager,selector,leased ? kCLDistanceFilterNone : value);
    // Main may commit a lease change between the check and the setter; settle on its state.
    if (session && session.distanceApplied!=leased)
        originalDistance(manager,selector,session.distanceApplied ? kCLDistanceFilterNone : session.requestedDistance);
}
#endif
// Like Distance, each hook settles on the lease state main may commit concurrently.
static void Background(CLLocationManager *manager,SEL selector,BOOL value) {
    GVMLocationSession *session=Session(manager);
    session.requestedBackground=value;
    BOOL leased=session.applied;
    originalBackground(manager,selector,leased ? YES : value);
    if (session && session.applied!=leased) originalBackground(manager,selector,session.applied ? YES : session.requestedBackground);
}
static void Pause(CLLocationManager *manager,SEL selector,BOOL value) {
    GVMLocationSession *session=Session(manager);
    session.requestedPause=value;
    BOOL leased=session.applied;
    originalPause(manager,selector,leased ? NO : value);
    if (session && session.applied!=leased) originalPause(manager,selector,session.applied ? NO : session.requestedPause);
}
static void Indicator(CLLocationManager *manager,SEL selector,BOOL value) {
    GVMLocationSession *session=Session(manager);
    session.requestedIndicator=value;
    BOOL leased=session.applied;
    originalIndicator(manager,selector,leased ? YES : value);
    if (session && session.applied!=leased) originalIndicator(manager,selector,session.applied ? YES : session.requestedIndicator);
}
// On a screen, the iPhone's or CarPlay's, the app is the user's: tell the supervisor so it never
// closes this process. SpringBoard's own process state does not count CarPlay scenes as foreground.
static void PublishShown(void) {
    static int token=-1;
    char name[96];
    snprintf(name,sizeof(name),GVM_BACKGROUND_SOURCE_SHOWN,(unsigned)ManagedSourceID());
    if (token<0 && notify_register_check(name,&token)!=NOTIFY_STATUS_OK) { token=-1; return; }
    uint64_t pid=(uint64_t)getpid(), previous=0;
    if (notify_get_state(token,&previous)==NOTIFY_STATUS_OK && previous==pid) return;
    notify_set_state(token,pid);
    notify_post(name);
    Record(@"app shown on a screen; GMapHUD will not close this process");
}
__attribute__((constructor)) static void ObserveShown(void) {
#if GVM_GOFA_SOURCE
    NSString *bundle=@"com.lumi.GOFA";
#elif GVM_WAZE_SOURCE
    NSString *bundle=@"com.waze.iphone";
#else
    NSString *bundle=@"vn.vietmap.live";
#endif
    // Any build of the source app: GMapHUD may have woken it even where its adapter is inactive.
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:bundle]) return;
    dispatch_async(dispatch_get_main_queue(),^{
        for (NSNotificationName name in @[UISceneWillEnterForegroundNotification,UISceneDidActivateNotification,
            UIApplicationWillEnterForegroundNotification,UIApplicationDidBecomeActiveNotification])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(__unused NSNotification *note) { PublishShown(); }];
        // Launched by the user straight to the screen, before the observers were in place.
        if (UIApplication.sharedApplication.applicationState!=UIApplicationStateBackground) PublishShown();
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if (scene.activationState==UISceneActivationStateForegroundActive ||
                scene.activationState==UISceneActivationStateForegroundInactive) PublishShown();
    });
}
__attribute__((constructor)) static void InitializeLocationSession(void) {
#if GVM_GOFA_SOURCE
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.lumi.GOFA"] ||
        ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"4.2.1"] ||
        ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"3"]) return;
#elif GVM_WAZE_SOURCE
    // Public CoreLocation calls only, so any Waze build; its native GPS start stays 5.25.0-only.
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.waze.iphone"]) return;
#else
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"vn.vietmap.live"]) return;
#endif
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIBackgroundModes"] containsObject:@"location"]) return;
    managers=[NSHashTable weakObjectsHashTable]; delegateClasses=[NSMutableSet new];
    if (notify_register_check(GVM_BACKGROUND_LOCATION_SESSION,&sessionToken)!=NOTIFY_STATUS_OK ||
        notify_register_check(GVM_BACKGROUND_LOCATION_SOURCE,&sourceSessionToken)!=NOTIFY_STATUS_OK) return;
    [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(__unused NSTimer *timer) {
        GVMRefreshLocationSession();
    }];
    #if GVM_WAZE_SOURCE
    MSHookMessageEx(CLLocationManager.class,@selector(startUpdatingHeading),(IMP)HeadingStart,(IMP *)&originalHeadingStart);
#endif
#if GVM_GOFA_SOURCE
    MSHookMessageEx(CLLocationManager.class,@selector(setDistanceFilter:),(IMP)Distance,(IMP *)&originalDistance);
#endif
    MSHookMessageEx(CLLocationManager.class,@selector(startUpdatingLocation),(IMP)Start,(IMP *)&originalStart);
    MSHookMessageEx(CLLocationManager.class,@selector(stopUpdatingLocation),(IMP)Stop,(IMP *)&originalStop);
    MSHookMessageEx(CLLocationManager.class,@selector(setDelegate:),(IMP)SetDelegate,(IMP *)&originalDelegate);
    MSHookMessageEx(CLLocationManager.class,@selector(setAllowsBackgroundLocationUpdates:),(IMP)Background,(IMP *)&originalBackground);
    MSHookMessageEx(CLLocationManager.class,@selector(setPausesLocationUpdatesAutomatically:),(IMP)Pause,(IMP *)&originalPause);
    MSHookMessageEx(CLLocationManager.class,@selector(setShowsBackgroundLocationIndicator:),(IMP)Indicator,(IMP *)&originalIndicator);
    Record(@"temporary location trial loaded; awaiting app GPS and visible Google Maps lease");
}
