#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "background-policy.h"
#import "placement-state.h"
#import "source-transport.h"
#include <notify.h>
#include <stdio.h>
#include <string.h>

static int heartbeatToken = -1, phoneToken=-1, permissionToken = -1, locationSessionToken=-1, sourceSessionToken=-1;
static int shownTokens[4]={-1,-1,-1,-1};
static id assertion;
static id locationUsageContext;
static pid_t heldPID;
static double nextLaunch, nextAssertion;
static double nextUsageContext;
static BOOL sessionActive;
static NSInteger lastPermission = NSIntegerMin;
static BOOL lastEnabled;
static NSString *providerID;
static NSUInteger managedSource;
static id carplayStatus;
static BOOL wasConnected, exitCompleted, exitDeferred;
static double disconnectedAt;
static pid_t managedPID;
// Wake attempts for the selected source in this session, the sources given up (bit per ID), and
// whether the live selection is a temporary fallback rather than the choice saved in Settings.
static unsigned failures, exhaustedSources, launchSerial;
static BOOL switchingSource, fallbackActive, gaveUp, lockNoted;
// The source process seen last tick, since when, and whether GMapHUD launched it (and may close it).
static pid_t trackedPID, ownedPID;
static double trackedSince, launchRequestedAt;
// Google Maps' process, so a new one starts a new session and a closed one ends it.
static pid_t lastGooglePID;
static double googleGoneAt;
static NSInteger cachedPermission=NSIntegerMin;
static BOOL cachedInstalled=YES, cachedServices=YES, wakeSwitch, exitSwitch;
static double nextPermissionCheck, nextSwitchRead, nextTickAt;
static NSString *BundleForSource(NSUInteger source) {
    if (!GVMSourceEnabled(source)) return nil;
    switch(source) {
        case GVMSourceVietMap: return @"vn.vietmap.live";
        case GVMSourceWaze: return @"com.waze.iphone";
        case GVMSourceGofa: return @"com.lumi.GOFA";
        default: return nil;
    }
}
static const char *Base(const char *type);
static BOOL BooleanPreference(CFStringRef key) {
    id value=CFBridgingRelease(CFPreferencesCopyAppValue(key,CFSTR("com.chou.gmaphud")));
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
static void ReadSwitches(void) {
    CFPreferencesAppSynchronize(CFSTR("com.chou.gmaphud"));
    wakeSwitch=BooleanPreference(CFSTR("autoWake")); exitSwitch=BooleanPreference(CFSTR("autoExit"));
}
static NSInteger LocationPermission(NSString *bundle) {
    Class manager=NSClassFromString(@"CLLocationManager");
    SEL selector=NSSelectorFromString(@"authorizationStatusForBundleIdentifier:");
    NSMethodSignature *signature=[manager methodSignatureForSelector:selector];
    if (!bundle || !signature || signature.numberOfArguments!=3 || strcmp(Base(signature.methodReturnType),"i") ||
        strcmp(Base([signature getArgumentTypeAtIndex:2]),"@")) return NSIntegerMin;
    return ((int (*)(id,SEL,id))objc_msgSend)(manager,selector,bundle);
}

static void Record(NSString *message) {
    NSString *path = @"/var/mobile/Library/Logs/gmaphud-background.log";
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if ([[fm attributesOfItemAtPath:path error:nil] fileSize] > 32768) [fm removeItemAtPath:path error:nil];
    if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [file seekToEndOfFile];
        [file writeData:[[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message] dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (__unused NSException *exception) {
    } @finally { [file closeFile]; }
}
static const char *Base(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL Matches(id object, NSString *name, const char *result, NSArray<NSString *> *arguments) {
    NSMethodSignature *signature = [object methodSignatureForSelector:NSSelectorFromString(name)];
    if (!signature || signature.numberOfArguments != arguments.count + 2 || strcmp(Base(signature.methodReturnType), result)) return NO;
    for (NSUInteger i=0; i<arguments.count; i++)
        if (strcmp(Base([signature getArgumentTypeAtIndex:i+2]), arguments[i].UTF8String)) return NO;
    return YES;
}
static id Shared(NSString *name, NSString *selector) {
    Class cls=NSClassFromString(name);
    return Matches(cls,selector,"@",@[]) ? ((id (*)(id,SEL))objc_msgSend)(cls,NSSelectorFromString(selector)) : nil;
}
static void ReleaseLocationUsage(void) {
    id previous=locationUsageContext; locationUsageContext=nil;
    nextUsageContext=0;
    if (previous && Matches(previous,@"invalidate","v",@[])) {
        ((void (*)(id,SEL))objc_msgSend)(previous,@selector(invalidate));
        Record(@"temporary location in-use context released");
    }
}
static void RefreshLocationUsage(NSInteger permission,BOOL active,double now) {
    if (!GVMBackgroundNeedsUsageContext((int)permission,active)) {
        ReleaseLocationUsage(); return;
    }
    if (locationUsageContext || now<nextUsageContext) return;
    nextUsageContext=now+30;
    Class cls=NSClassFromString(@"CLInUseAssertion");
    NSString *name=@"newAssertionForBundleIdentifier:withReason:";
    Method end=class_getInstanceMethod(cls,@selector(invalidate));
    NSMethodSignature *signature=end ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(end)] : nil;
    if (!Matches(cls,name,"@",@[@"@",@"@"]) || !signature ||
        signature.numberOfArguments!=2 || strcmp(Base(signature.methodReturnType),"v")) {
        Record(@"temporary location in-use context unavailable: private ABI"); return;
    }
    // The new-family factory returns an owned assertion; this does not alter authorization.
    @try {
        void *owned=((void * (*)(id,SEL,id,id))objc_msgSend)(cls,NSSelectorFromString(name),
            providerID,@"GMapHUD visible Google Maps source");
        locationUsageContext=(__bridge_transfer id)owned;
        Record([NSString stringWithFormat:@"temporary location in-use context requested=%d; GPS activation unverified",locationUsageContext!=nil]);
    } @catch (NSException *exception) {
        Record([@"temporary location in-use context request failed: " stringByAppendingString:exception.name]);
    }
}
static void Release(void) {
    id previous=assertion; assertion=nil; heldPID=0;
    if (previous && Matches(previous,@"invalidate","v",@[])) {
        ((void (*)(id,SEL))objc_msgSend)(previous,NSSelectorFromString(@"invalidate"));
        Record(@"background execution released");
    }
}
static BOOL Acquire(pid_t pid) {
    Class attributeClass=NSClassFromString(@"RBSDomainAttribute"), targetClass=NSClassFromString(@"RBSTarget");
    id candidate=[NSClassFromString(@"RBSAssertion") alloc];
    if (!Matches(attributeClass,@"attributeWithDomain:name:","@",@[@"@",@"@"]) ||
        !Matches(targetClass,@"targetWithPid:","@",@[@"i"]) ||
        !Matches(candidate,@"initWithExplanation:target:attributes:","@",@[@"@",@"@",@"@"]) ||
        !Matches(candidate,@"acquireWithError:","B",@[@"^@"]) || !Matches(candidate,@"invalidate","v",@[])) {
        Record(@"background execution unavailable: private ABI"); return NO;
    }
    id attribute=((id (*)(id,SEL,id,id))objc_msgSend)(attributeClass,NSSelectorFromString(@"attributeWithDomain:name:"),@"com.apple.frontboard",@"Workspace-BackgroundActive");
    id target=((id (*)(id,SEL,pid_t))objc_msgSend)(targetClass,NSSelectorFromString(@"targetWithPid:"),pid);
    if (!attribute || !target) return NO;
    candidate=((id (*)(id,SEL,id,id,id))objc_msgSend)(candidate,NSSelectorFromString(@"initWithExplanation:target:attributes:"),@"GMapHUD visible Google Maps source",target,@[attribute]);
    NSError *error=nil;
    BOOL acquired=((BOOL (*)(id,SEL,NSError *__autoreleasing *))objc_msgSend)(candidate,NSSelectorFromString(@"acquireWithError:"),&error);
    Record([NSString stringWithFormat:@"background execution acquired=%d error=%@ code=%ld",acquired,error.domain ?: @"none",(long)error.code]);
    if (acquired) { assertion=candidate; heldPID=pid; }
    else if (candidate) ((void (*)(id,SEL))objc_msgSend)(candidate,NSSelectorFromString(@"invalidate"));
    return acquired;
}
// FrontBoard refuses some launches while the phone is locked; that is not the source's failure.
static BOOL LockedError(NSError *error) {
    for (unsigned depth=0;error && depth<5;depth++) {
        if (([error.domain isEqual:@"FBSOpenApplicationErrorDomain"] && error.code==7) ||
            [error.userInfo[@"BSErrorCodeDescription"] isEqual:@"Locked"]) return YES;
        id underlying=error.userInfo[NSUnderlyingErrorKey];
        error=[underlying isKindOfClass:NSError.class] ? underlying : nil;
    }
    return NO;
}
static void Launch(void) {
    id service=Shared(@"FBSOpenApplicationService",@"serviceWithDefaultShellEndpoint");
    Class optionsClass=NSClassFromString(@"FBSOpenApplicationOptions");
    if (!Matches(service,@"openApplication:withOptions:completion:","v",@[@"@",@"@",@"@?"]) ||
        !Matches(optionsClass,@"optionsWithDictionary:","@",@[@"@"])) {
        Record(@"background launch unavailable: private ABI"); return;
    }
    id options=((id (*)(id,SEL,id))objc_msgSend)(optionsClass,NSSelectorFromString(@"optionsWithDictionary:"),
        @{@"__ActivateSuspended":@YES,@"__PromptUnlockDevice":@NO,@"__UnlockDevice":@NO});
    if (!options) return;
    NSString *bundle=providerID;
    unsigned attempt=failures, serial=++launchSerial;
    void (^completion)(id,NSError *)=^(__unused id process,NSError *error) {
        if (!error) return;
        dispatch_async(dispatch_get_main_queue(),^{
            BOOL locked=LockedError(error);
            // A launch refused because the phone is locked is retried later without counting; only the
            // latest attempt is given back, so a late reply cannot cancel a newer count.
            if (locked) {
                if (serial==launchSerial && [bundle isEqual:providerID] && failures) { failures--; nextLaunch=NSProcessInfo.processInfo.systemUptime+10; }
                if (!lockNoted) { lockNoted=YES; Record([NSString stringWithFormat:@"launch of %@ refused while locked; retrying without counting",bundle]); }
                return;
            }
            Record([NSString stringWithFormat:@"launch %u of %@ failed: %@ %ld",attempt,bundle,error.domain,(long)error.code]);
        });
    };
    launchRequestedAt=NSProcessInfo.processInfo.systemUptime;
    ((void (*)(id,SEL,id,id,id))objc_msgSend)(service,NSSelectorFromString(@"openApplication:withOptions:completion:"),providerID,options,completion);
    Record([NSString stringWithFormat:@"suspended launch %u/%d requested for %@",attempt,GVMWakeAttempts,bundle]);
}
static BOOL Installed(NSString *bundle) {
    Class workspaceClass=NSClassFromString(@"LSApplicationWorkspace");
    id workspace=Matches(workspaceClass,@"defaultWorkspace","@",@[]) ?
        ((id (*)(id,SEL))objc_msgSend)(workspaceClass,NSSelectorFromString(@"defaultWorkspace")) : nil;
    // Without the private check every app counts as installed: one without location permission is
    // then neither woken nor counted, and a fallback goes to any source with permission.
    if (!Matches(workspace,@"applicationIsInstalled:","B",@[@"@"])) return YES;
    return ((BOOL (*)(id,SEL,id))objc_msgSend)(workspace,NSSelectorFromString(@"applicationIsInstalled:"),bundle);
}
// Sources worth falling back to: installed, enabled and allowed to use location.
static unsigned AvailableSources(void) {
    unsigned available=0;
    for (NSUInteger source=1;source<=3;source++) {
        NSString *bundle=BundleForSource(source);
        if (bundle && Installed(bundle) && GVMBackgroundLocationAuthorized((int)LocationPermission(bundle))) available|=1u<<source;
    }
    return available;
}
// Whether the app is on a screen, the iPhone's or CarPlay's: SpringBoard's own process state. When
// that cannot be read the app counts as visible, so it is never closed blind.
static BOOL Visible(NSString *bundle) {
    Class controllerClass=NSClassFromString(@"SBApplicationController");
    id controller=Matches(controllerClass,@"sharedInstance","@",@[]) ?
        ((id (*)(id,SEL))objc_msgSend)(controllerClass,NSSelectorFromString(@"sharedInstance")) : nil;
    if (!bundle || !Matches(controller,@"applicationWithBundleIdentifier:","@",@[@"@"])) return YES;
    id application=((id (*)(id,SEL,id))objc_msgSend)(controller,NSSelectorFromString(@"applicationWithBundleIdentifier:"),bundle);
    if (!Matches(application,@"processState","@",@[])) return YES;
    id state=((id (*)(id,SEL))objc_msgSend)(application,NSSelectorFromString(@"processState"));
    if (!state) return NO;
    if (!Matches(state,@"isForeground","B",@[])) return YES;
    return ((BOOL (*)(id,SEL))objc_msgSend)(state,NSSelectorFromString(@"isForeground"));
}
static void ClearLease(void) {
    if (locationSessionToken>=0) notify_set_state(locationSessionToken,0);
    if (sourceSessionToken>=0) notify_set_state(sourceSessionToken,0);
    ReleaseLocationUsage(); Release();
    sessionActive=NO; failures=0; nextLaunch=0; nextAssertion=0;
}
static pid_t PID(id service,NSString *bundle) {
    if (!bundle || !Matches(service,@"pidForApplication:","i",@[@"@"])) return 0;
    return ((pid_t (*)(id,SEL,id))objc_msgSend)(service,NSSelectorFromString(@"pidForApplication:"),bundle);
}
static void Terminate(id service,NSString *bundle,NSUInteger source,pid_t pid,NSString *reason) {
    if (!Matches(service,@"terminateApplication:forReason:andReport:withDescription:","v",@[@"@",@"q",@"B",@"@"])) return;
    ((void (*)(id,SEL,id,NSInteger,BOOL,id))objc_msgSend)(service,
        NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:"),bundle,1,NO,reason);
    Record([NSString stringWithFormat:@"close requested source=%lu pid=%d reason=%@",(unsigned long)source,pid,reason]);
}
// Whether this source process reported a scene in the foreground, on the iPhone or on CarPlay.
static BOOL Shown(NSUInteger source,pid_t pid) {
    uint64_t shown=0;
    if (source<4 && shownTokens[source]>=0) notify_get_state(shownTokens[source],&shown);
    return pid>0 && shown==(uint64_t)pid;
}
// Closes the source only if GMapHUD launched this very process and it has never been on a screen;
// an app the user opened, or one shown on the iPhone or CarPlay, is theirs.
static void CloseOwned(id service,NSString *bundle,NSUInteger source,NSString *reason) {
    pid_t pid=PID(service,bundle);
    if (pid>0 && pid==ownedPID && !Shown(source,pid) && !Visible(bundle)) Terminate(service,bundle,source,pid,reason);
    ownedPID=0; trackedPID=0;
}
// Auto-exit after a CarPlay disconnect (its own Settings switch) keeps its earlier rule: the process
// running while CarPlay was connected, unless it is on a screen.
static void CloseManaged(id service,NSString *bundle,NSUInteger source,NSString *reason) {
    pid_t pid=PID(service,bundle);
    if (pid>0 && pid==managedPID && !Visible(bundle)) Terminate(service,bundle,source,pid,reason);
    managedPID=0;
}
// The selected source's process, followed on every tick: whether GMapHUD launched it (a process that
// appeared within 15 s of GMapHUD's own launch request) and whether it has been on a screen since.
static pid_t Track(id service,NSUInteger source,double now) {
    pid_t pid=PID(service,providerID);
    if (pid<=0) { trackedPID=0; ownedPID=0; return 0; }
    if (pid!=trackedPID) {
        trackedPID=pid; trackedSince=now;
        ownedPID=GVMWakeOwnsProcess(launchRequestedAt,now) ? pid : 0;
        Record([NSString stringWithFormat:@"source %lu pid %d running; launched by GMapHUD=%d",(unsigned long)source,pid,ownedPID==pid]);
    }
    // On the iPhone's screen or CarPlay's, it is the user's from now on. The app reports its own
    // scenes (CarPlay included); SpringBoard's process state covers the iPhone only.
    BOOL reported=Shown(source,pid);
    if (ownedPID==pid && (reported || Visible(providerID))) {
        ownedPID=0;
        Record([NSString stringWithFormat:@"source %lu pid %d shown on screen (reported by app=%d); GMapHUD will not close it",(unsigned long)source,pid,reported]);
    }
    return pid;
}
// Restores the choice saved in Settings in place of a fallback. With `keepGivenUp` the sources given
// up stay given up (the restore is not a new choice). Returns whether the live selection moved.
static BOOL RestoreSaved(BOOL keepGivenUp) {
    fallbackActive=NO;
    NSUInteger before=GVMSelectedSourceID();
    switchingSource=keepGivenUp;
    GVMRestoreOutputSelection();
    BOOL moved=GVMSelectedSourceID()!=before;
    if (!moved) switchingSource=NO;
    return moved;
}
// A new Google Maps session: the saved choice gets another chance and nothing stays given up.
// Returns whether the selection moved, so the caller leaves the rest to the next tick.
static BOOL NewSession(void) {
    exhaustedSources=0; gaveUp=NO; lockNoted=NO; failures=0; nextLaunch=0;
    if (!fallbackActive) return NO;
    BOOL moved=RestoreSaved(NO);
    Record(@"new Google Maps session; saved source restored");
    return moved;
}
// After five failed wakes the next usable source takes over for this session, without changing the
// choice saved in Settings.
static void SwitchSource(NSUInteger from) {
    exhaustedSources|=1u<<from;
    unsigned next=GVMWakeFallbackSource(AvailableSources(),exhaustedSources);
    if (!next) {
        // No more launches this session; a source the user opens is still kept awake, and the saved
        // choice is live again so that it can publish.
        gaveUp=YES;
        Record([NSString stringWithFormat:@"source %lu failed %d wakes; no other usable source, waking stops for this session",(unsigned long)from,GVMWakeAttempts]);
        if (fallbackActive) RestoreSaved(YES);
        return;
    }
    switchingSource=YES;
    if (GVMSelectOutputSourceForNow(next)) {
        fallbackActive=YES;
        Record([NSString stringWithFormat:@"source %lu failed %d wakes; switched to source %u for this session",(unsigned long)from,GVMWakeAttempts,next]);
    } else switchingSource=NO;
}
static void SafeTick(void);
static void Tick(void) {
    double now=NSProcessInfo.processInfo.systemUptime;
    // Busy (a map shown, a countdown running, a wake in progress) ticks every second; idle every five.
    if (now<nextTickAt) return;
    nextTickAt=now+4.9;
    id service=Shared(@"FBSSystemService",@"sharedService");
    NSUInteger selected=GVMSelectedSourceID();
    if (!selected) return;  // the selection could not be read; change nothing
    if (now>=nextSwitchRead) { ReadSwitches(); nextSwitchRead=now+5; }
    BOOL enabled=wakeSwitch;
    if (selected!=managedSource) {
        // A launch of the previous source still under way: follow it for up to 3 s, so that its
        // process is known and can be closed below.
        if (providerID && trackedPID<=0 && launchRequestedAt>0 && now-launchRequestedAt<GVMWakeInterval) {
            Track(service,managedSource,now);
            if (trackedPID<=0) { nextTickAt=0; return; }
        }
        NSString *previous=providerID;
        NSUInteger previousSource=managedSource;
        ClearLease();
        // One source at a time: the one GMapHUD woke and nobody has looked at closes.
        CloseOwned(service,previous,previousSource,@"GMapHUD warning source changed");
        providerID=BundleForSource(selected); managedSource=selected; disconnectedAt=0;
        ownedPID=0; trackedPID=0; launchRequestedAt=0;
        // A choice made in Settings (or a restored one) starts afresh; a fallback keeps what was given up.
        if (!switchingSource) { exhaustedSources=0; gaveUp=NO; fallbackActive=NO; }
        switchingSource=NO; nextPermissionCheck=0;
        Record([NSString stringWithFormat:@"selected source=%lu",(unsigned long)selected]);
    }
    pid_t pid=Track(service,selected,now);
    // Google Maps' process: a new one is a new session; one gone for 10 s ends the session and the
    // source GMapHUD woke for it exits.
    pid_t clientPID=PID(service,@"com.google.Maps");
    if (clientPID>0) {
        BOOL renewed=lastGooglePID>0 && clientPID!=lastGooglePID;
        lastGooglePID=clientPID; googleGoneAt=0;
        // The restored source is handled by the selection change, not by the rest of this tick.
        if (renewed && NewSession()) return;
    } else if (lastGooglePID>0 && googleGoneAt<=0) googleGoneAt=now;
    if (GVMHostExitDue(now,googleGoneAt)) {
        ClearLease();
        CloseOwned(service,providerID,managedSource,@"GMapHUD Google Maps closed");
        lastGooglePID=0; googleGoneAt=0;
        if (NewSession()) return;
    }
    BOOL connected=carplayStatus && Matches(carplayStatus,@"currentSession","@",@[]) &&
        ((id (*)(id,SEL))objc_msgSend)(carplayStatus,NSSelectorFromString(@"currentSession"))!=nil;
    uint64_t heartbeat=0,phoneHeartbeat=0;
    if (heartbeatToken>=0) notify_get_state(heartbeatToken,&heartbeat);
    if (phoneToken>=0) notify_get_state(phoneToken,&phoneHeartbeat);
    BOOL phoneVisible=GVMBackgroundActive(now,phoneHeartbeat);
    if (connected) { disconnectedAt=0; exitCompleted=NO; }
    else if (wasConnected) {
        disconnectedAt=now;
        Record(@"CarPlay disconnected; 20 second exit countdown started");
    }
    wasConnected=connected;
    BOOL autoExit=exitSwitch;
    if (!autoExit) { disconnectedAt=0; exitCompleted=NO; }
    // Google Maps visible on the iPhone is still in use: restart the exit countdown from when
    // it is hidden, and let it wake a source that auto-exit already closed.
    if (phoneVisible && (disconnectedAt>0 || exitCompleted)) {
        if (!exitDeferred) Record(@"iPhone Google Maps visible; CarPlay exit deferred");
        exitDeferred=YES; exitCompleted=NO;
        if (disconnectedAt>0) disconnectedAt=now;
    } else exitDeferred=NO;
    if (connected && autoExit && pid>0) managedPID=pid;
    if (autoExit && !connected && GVMBackgroundDisconnectDue(now,disconnectedAt)) {
        ClearLease(); CloseManaged(service,providerID,managedSource,@"GMapHUD CarPlay disconnected for 20 seconds");
        disconnectedAt=0; exitCompleted=YES;
    }
    // Permission, Location Services and installation change rarely; ask every five seconds.
    if (now>=nextPermissionCheck) {
        cachedPermission=LocationPermission(providerID);
        cachedServices=CLLocationManager.locationServicesEnabled;
        cachedInstalled=!providerID || Installed(providerID);
        nextPermissionCheck=now+5;
    }
    NSInteger permission=cachedPermission;
    BOOL allowed=GVMBackgroundLocationAuthorized((int)permission) && cachedServices;
    if (permissionToken>=0) notify_set_state(permissionToken,GVMBackgroundPermissionState(now,allowed));
    if (enabled!=lastEnabled || permission!=lastPermission) {
        Record([NSString stringWithFormat:@"automatic wake enabled=%d source=%lu permission=%ld",enabled,(unsigned long)selected,(long)permission]);
        lastEnabled=enabled; lastPermission=permission;
    }
    // CarPlay connection is distinct from a visible-map heartbeat.
    BOOL hostActive=GVMBackgroundAnyHostActive(now,connected ? heartbeat : 0,phoneHeartbeat);
    // A little under a second, so that a timer fire that comes early does not skip a whole tick.
    if (hostActive || disconnectedAt>0 || googleGoneAt>0) nextTickAt=now+0.9;
    BOOL active=enabled && providerID && hostActive &&
        !GVMBackgroundExitHolds(autoExit,connected,phoneVisible,disconnectedAt,exitCompleted);
    if (!active || clientPID<=0) { ClearLease(); return; }
    // An installed source without location permission is not woken; one that is not installed is
    // given up after the same five attempts as one that keeps crashing.
    if (!allowed && cachedInstalled) { ClearLease(); return; }
    // After giving up, only a source that is already running (one the user opened) is kept awake.
    if (gaveUp && pid<=0) { ClearLease(); return; }
    if (!sessionActive) { sessionActive=YES; Record(@"selected source supervisor started"); }
    if (sourceSessionToken>=0) notify_set_state(sourceSessionToken,selected);
    if (locationSessionToken>=0) notify_set_state(locationSessionToken,GVMBackgroundPermissionState(now,YES));
    RefreshLocationUsage(permission,YES,now);
    if (heldPID && heldPID!=pid) { Release(); nextAssertion=0; }
    if (pid>0) {
        // Output sampled after this process started, from a process alive for 10 s, proves the wake.
        if (failures) {
            NSDictionary *output=GVMReadSourceOutput(now);
            double newest=-1;
            if ([output[@"sourceID"] unsignedIntegerValue]==selected)
                for (NSString *field in @[@"speed",@"speedLimit"])
                    newest=MAX(newest,[output[field][@"receivedAt"] doubleValue]);
            if (GVMWakeProven(now,trackedSince,newest)) {
                Record([NSString stringWithFormat:@"source %lu publishing after %u wake attempt(s)",(unsigned long)selected,failures]);
                failures=0;
            }
        }
        // Acquiring a background-active assertion resumes a suspended process as well.
        if (!assertion && now>=nextAssertion) { nextAssertion=now+30; Acquire(pid); }
        return;
    }
    if (GVMWakeSwitchDue(now,nextLaunch,failures)) { SwitchSource(selected); return; }
    if (GVMWakeMayLaunch(now,nextLaunch,failures)) {
        failures++; nextLaunch=now+GVMWakeInterval; Launch();
        // Check again exactly when the next attempt is allowed, not on the next whole-second tick,
        // so five attempts take 15 seconds.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((GVMWakeInterval+0.01)*NSEC_PER_SEC)),
            dispatch_get_main_queue(),^{ nextTickAt=0; SafeTick(); });
    }
}
static void SafeTick(void) {
    @try { Tick(); }
    @catch (__unused NSException *exception) {
        @try { ReleaseLocationUsage(); } @catch (__unused NSException *cleanup) {}
        @try { Release(); } @catch (__unused NSException *cleanup) {}
        nextUsageContext=NSProcessInfo.processInfo.systemUptime+30;
        nextAssertion=NSProcessInfo.processInfo.systemUptime+30;
    }
}
__attribute__((constructor)) static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    dlopen("/System/Library/PrivateFrameworks/CarKit.framework/CarKit",RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",RTLD_NOW);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (notify_register_check(GVM_BACKGROUND_SIGNAL,&heartbeatToken)!=NOTIFY_STATUS_OK) return;
        notify_register_check(GVM_BACKGROUND_PHONE_SIGNAL,&phoneToken);
        notify_register_check(GVM_BACKGROUND_PERMISSION,&permissionToken);
        notify_register_check(GVM_BACKGROUND_LOCATION_SESSION,&locationSessionToken);
        notify_register_check(GVM_BACKGROUND_LOCATION_SOURCE,&sourceSessionToken);
        Class statusClass=NSClassFromString(@"CARSessionStatus");
        if (Matches(statusClass,@"new","@",@[])) carplayStatus=[statusClass new];
        SafeTick();
        Record(@"supervisor loaded; awaiting visible Google Maps on CarPlay or iPhone");
        // Common modes, so ticks continue while SpringBoard tracks a touch.
        [NSRunLoop.mainRunLoop addTimer:[NSTimer timerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) { SafeTick(); }]
            forMode:NSRunLoopCommonModes];
        // A map shown again, or a source chosen in Settings, is handled now rather than on the next
        // idle tick.
        dispatch_block_t tickNow=^{ nextTickAt=0; SafeTick(); };
        const char *signals[]={GVM_BACKGROUND_SIGNAL,GVM_BACKGROUND_PHONE_SIGNAL};
        int token=-1;
        for (unsigned i=0;i<2;i++)
            notify_register_dispatch(signals[i],&token,dispatch_get_main_queue(),^(__unused int fired) { tickNow(); });
        GVMObserveSelection(dispatch_get_main_queue(),tickNow);
        notify_register_dispatch(GVMSizeChangedName,&token,dispatch_get_main_queue(),^(__unused int fired) {
            nextSwitchRead=0; tickNow();
        });
        for (unsigned source=1;source<4;source++) {
            char name[96];
            snprintf(name,sizeof(name),GVM_BACKGROUND_SOURCE_SHOWN,source);
            notify_register_check(name,&shownTokens[source]);
            notify_register_dispatch(name,&token,dispatch_get_main_queue(),^(__unused int fired) { tickNow(); });
        }
    });
}
