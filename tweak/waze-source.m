#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <notify.h>
#import "alert-state.h"
#import "waze-output.h"
#import "source-transport.h"
#import "speed-state.h"
#include "waze-limit-search.h"
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif
#include <string.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/getsect.h>
#include <math.h>

static GVMWazeOutputStore *store;
static int requestToken=-1;
static double lastStatusTime=-1;
static void Publish(BOOL force);
// Bounded support inventory; no IDs, coordinates, titles or accounts.
static void ObserveAlert(NSString *icon,NSInteger type,NSInteger subtype,NSInteger trait,
                         NSInteger distance,BOOL valid,BOOL passed,double uptime) {
    if (![icon isKindOfClass:NSString.class] || icon.length>128 || !isfinite(uptime)) return;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([icon rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound) return;
    static NSMutableDictionary *catalog;
    static BOOL pending;
    if (!catalog) catalog=[NSMutableDictionary new];
    NSString *key=[NSString stringWithFormat:@"%ld:%ld:%ld:%@",(long)type,(long)subtype,(long)trait,icon];
    NSDictionary *previous=catalog[key];
    if (!previous && catalog.count>=64) return;
    if (previous && [previous[@"valid"] boolValue]==valid && [previous[@"passed"] boolValue]==passed) return;
    catalog[key]=@{@"icon":icon,@"type":@(type),@"subtype":@(subtype),@"trait":@(trait),
        @"distance":distance>=0 && distance<=10000 ? @(distance) : NSNull.null,
        @"valid":@(valid),@"passed":@(passed),@"uptime":@(uptime),
        @"appState":@(UIApplication.sharedApplication.applicationState)};
    // Coalesce semantic/lifecycle changes; never renew source timestamps.
    if (pending) return;
    pending=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        pending=NO;
        NSData *data=[NSJSONSerialization dataWithJSONObject:catalog.allValues options:NSJSONWritingSortedKeys error:nil];
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-alert-catalog.json"] atomically:YES];
    });
}

static uint64_t (*ReadNativeLimit)(void);
// Set once a native GPS position has been processed, so the native limit state exists.
static BOOL nativeLimitReady;
static NSString *limitGuardStatus=@"not checked";
typedef id (*GPSInit)(id __attribute__((ns_consumed)),SEL,double,double,double,double,double,double,double,BOOL,double,double) __attribute__((ns_returns_retained));
static GPSInit OriginalGPS;
static id GPS(id self __attribute__((ns_consumed)),SEL cmd,double longitude,double latitude,double altitude,
 double speed,double steering,double accuracy,double time,BOOL hasSteering,double speedAccuracy,double steeringAccuracy) __attribute__((ns_returns_retained));
static id GPS(id self __attribute__((ns_consumed)),SEL cmd,double longitude,double latitude,double altitude,
 double speed,double steering,double accuracy,double time,BOOL hasSteering,double speedAccuracy,double steeringAccuracy) {
    id result=OriginalGPS(self,cmd,longitude,latitude,altitude,speed,steering,accuracy,time,hasSteering,speedAccuracy,steeringAccuracy);
    double now=NSDate.date.timeIntervalSince1970;
    double uptime=NSProcessInfo.processInfo.systemUptime;
    dispatch_async(dispatch_get_main_queue(), ^{
        // A delayed queue must not make the original GPS sample fresh again.
        double current=NSProcessInfo.processInfo.systemUptime;
        if (current-uptime>=5) { [store endStationaryHold]; return; }
        // The getter runs only for the selected source, so a Waze kept for other uses is left alone.
        uint64_t limit=ReadNativeLimit && GVMSelectedSourceID()==GVMSourceWaze ? ReadNativeLimit() : 0;
        nativeLimitReady=ReadNativeLimit!=NULL;
        [store updateSpeed:speed timestamp:time now:now uptime:uptime optionalLimit:limit];
        Publish(NO);
        if (lastStatusTime<0 || current-lastStatusTime>=5) {
            lastStatusTime=current;
            NSDictionary *output=[store outputAtUptime:current];
            NSString *line=[NSString stringWithFormat:@"speed=%@ limit=%@ guard=%@ appState=%ld rawMMSec=%.2f sampleAge=%.3f uptime=%.2f",
                output[@"speed"][@"value"] ?: @"unavailable",output[@"speedLimit"][@"value"] ?: @"unavailable",
                limitGuardStatus,(long)UIApplication.sharedApplication.applicationState,speed,now-time,current];
            [line writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-gps.status"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    });
    return result;
}
// Waze's native current-limit getter. 5.25.0 has it at a measured address; other builds are
// searched for the same code once (cached per build UUID), off the main thread.
static void UseNativeLimit(const uint32_t *reader,NSString *status) {
    void *address=(void *)reader;
#if __has_feature(ptrauth_calls)
    address=ptrauth_sign_unauthenticated(address,ptrauth_key_function_pointer,0);
#endif
    ReadNativeLimit=(uint64_t (*)(void))address;
    limitGuardStatus=status;
}
static void ConfigureNativeLimit(void) {
    const struct mach_header_64 *image=NULL;
    intptr_t slide=0;
    // Injection can reorder dyld images: take the app executable itself.
    for (uint32_t i=0;i<_dyld_image_count() && !image;i++) {
        const struct mach_header_64 *header=(const struct mach_header_64 *)_dyld_get_image_header(i);
        if (header && header->magic==MH_MAGIC_64 && header->filetype==MH_EXECUTE) { image=header; slide=_dyld_get_image_vmaddr_slide(i); }
    }
    unsigned long size=0;
    const uint32_t *text=image ? (const uint32_t *)getsectiondata(image,"__TEXT","__text",&size) : NULL;
    if (!text) { limitGuardStatus=@"Waze text not found"; return; }
    size_t count=size/4;
    NSString *uuid=nil;
    const struct load_command *command=(const struct load_command *)(image+1);
    for (uint32_t i=0;i<image->ncmds && !uuid;i++) {
        if (command->cmd==LC_UUID)
            uuid=[[NSUUID alloc] initWithUUIDBytes:((const struct uuid_command *)command)->uuid].UUIDString;
        command=(const struct load_command *)((const uint8_t *)command+command->cmdsize);
    }
    if (!uuid) { limitGuardStatus=@"Waze image UUID missing"; return; }
    if ([uuid isEqual:@"90947E86-BFF2-3434-A28B-979C65DB8846"]) {
        long index=GVMWazeLimitReaderIndex(text,count,(uintptr_t)slide+0x101028ff4);
        if (index>=0) UseNativeLimit(text+index,@"matched 5.25.0");
        else limitGuardStatus=@"5.25.0 limit getter changed";
        return;
    }
    // One search per build: its result, found or not, is kept with the search version.
    NSString *cache=[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-limit-reader.plist"];
    NSDictionary *known=[NSDictionary dictionaryWithContentsOfFile:cache];
    NSNumber *cached=[known[@"search"] isEqual:@(GVMWazeLimitSearchVersion)] ? known[uuid] : nil;
    if ([cached isKindOfClass:NSNumber.class] && cached.longLongValue<0) {
        limitGuardStatus=@"limit getter not found in this build (searched earlier)";
        return;
    }
    if ([cached isKindOfClass:NSNumber.class] && GVMWazeLimitReaderAt(text,count,(size_t)cached.longLongValue)) {
        UseNativeLimit(text+cached.longLongValue,@"found earlier for this build");
        return;
    }
    limitGuardStatus=@"searching";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        long index=GVMFindWazeLimitReader(text,count);
        dispatch_async(dispatch_get_main_queue(),^{
            [@{@"search":@(GVMWazeLimitSearchVersion),uuid:@(index)} writeToFile:cache atomically:YES];
            if (index<0) { limitGuardStatus=@"limit getter not found in this build"; return; }
            UseNativeLimit(text+index,@"found by code search");
        });
    });
}
// The cold GPS retry needs the time of a real sample; a held speed is not one.
double GVMWazeLastGPSSample(void) { return store ? store.lastSampleUptime : -1; }
// A held stationary speed belongs to the GPS run that measured it.
void GVMWazeEndStationaryHold(void) {
    if (NSThread.isMainThread) [store endStationaryHold];
    else dispatch_async(dispatch_get_main_queue(), ^{ [store endStationaryHold]; });
}
static void Status(NSString *message) {
    [message writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-waze-source.status"]
             atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void Publish(BOOL force) {
    double now=NSProcessInfo.processInfo.systemUptime;
    GVMPublishSourceOutput([store outputAtUptime:now],now,force);
}

// Signature measured in Waze 5.25.0 and checked by type encoding at load. Preserve init-family
// ownership and all arguments.
typedef id (*DescriptorInit)(id __attribute__((ns_consumed)), SEL, id alertId, NSInteger priority, BOOL isPreemptive, BOOL isValid, NSInteger distanceMeters, id title, id carplayTitle, id alertDescription, id carplayAlertDescription, id iconName, BOOL isCancellable, BOOL canSendThumbsUp, BOOL isCloseOnly, id primaryButtonText, id secondaryButtonText, BOOL disableCompactEtaBarTaps, BOOL showDistance, BOOL keepOpenAfterAction, BOOL closeOnlyOnSelection, double timeoutSeconds, NSInteger timerType, id zoneAlertData, BOOL shouldShowStillThere, BOOL didPassAlert, NSInteger triggerDistanceMeters, BOOL primaryButtonIsClose, BOOL secondaryButtonIsClose, BOOL shouldShowFocusedAlert, NSInteger silentActivationReason, id coordinate, BOOL shouldCheckDistanceFromLastAlert, NSInteger statsAlertId, NSInteger statsType, NSInteger statsSubtype, NSInteger statsSubtypeTrait, id statsUniqueId, BOOL dismissImmediatelyUponRemoval, BOOL isApproachingWithValidationHasValue, BOOL isApproachingWithValidation, BOOL hideActionsWhenInvalid, BOOL showOnCarPlayDashboard, BOOL doNotHideOnMapMovement) __attribute__((ns_returns_retained));
static DescriptorInit OriginalDescriptor;
static id Descriptor(id self __attribute__((ns_consumed)), SEL cmd, id alertId, NSInteger priority, BOOL isPreemptive, BOOL isValid, NSInteger distanceMeters, id title, id carplayTitle, id alertDescription, id carplayAlertDescription, id iconName, BOOL isCancellable, BOOL canSendThumbsUp, BOOL isCloseOnly, id primaryButtonText, id secondaryButtonText, BOOL disableCompactEtaBarTaps, BOOL showDistance, BOOL keepOpenAfterAction, BOOL closeOnlyOnSelection, double timeoutSeconds, NSInteger timerType, id zoneAlertData, BOOL shouldShowStillThere, BOOL didPassAlert, NSInteger triggerDistanceMeters, BOOL primaryButtonIsClose, BOOL secondaryButtonIsClose, BOOL shouldShowFocusedAlert, NSInteger silentActivationReason, id coordinate, BOOL shouldCheckDistanceFromLastAlert, NSInteger statsAlertId, NSInteger statsType, NSInteger statsSubtype, NSInteger statsSubtypeTrait, id statsUniqueId, BOOL dismissImmediatelyUponRemoval, BOOL isApproachingWithValidationHasValue, BOOL isApproachingWithValidation, BOOL hideActionsWhenInvalid, BOOL showOnCarPlayDashboard, BOOL doNotHideOnMapMovement) __attribute__((ns_returns_retained));
static id Descriptor(id self __attribute__((ns_consumed)), SEL cmd, id alertId, NSInteger priority, BOOL isPreemptive, BOOL isValid, NSInteger distanceMeters, id title, id carplayTitle, id alertDescription, id carplayAlertDescription, id iconName, BOOL isCancellable, BOOL canSendThumbsUp, BOOL isCloseOnly, id primaryButtonText, id secondaryButtonText, BOOL disableCompactEtaBarTaps, BOOL showDistance, BOOL keepOpenAfterAction, BOOL closeOnlyOnSelection, double timeoutSeconds, NSInteger timerType, id zoneAlertData, BOOL shouldShowStillThere, BOOL didPassAlert, NSInteger triggerDistanceMeters, BOOL primaryButtonIsClose, BOOL secondaryButtonIsClose, BOOL shouldShowFocusedAlert, NSInteger silentActivationReason, id coordinate, BOOL shouldCheckDistanceFromLastAlert, NSInteger statsAlertId, NSInteger statsType, NSInteger statsSubtype, NSInteger statsSubtypeTrait, id statsUniqueId, BOOL dismissImmediatelyUponRemoval, BOOL isApproachingWithValidationHasValue, BOOL isApproachingWithValidation, BOOL hideActionsWhenInvalid, BOOL showOnCarPlayDashboard, BOOL doNotHideOnMapMovement) {
    id result = OriginalDescriptor(self, cmd, alertId, priority, isPreemptive, isValid, distanceMeters, title, carplayTitle, alertDescription, carplayAlertDescription, iconName, isCancellable, canSendThumbsUp, isCloseOnly, primaryButtonText, secondaryButtonText, disableCompactEtaBarTaps, showDistance, keepOpenAfterAction, closeOnlyOnSelection, timeoutSeconds, timerType, zoneAlertData, shouldShowStillThere, didPassAlert, triggerDistanceMeters, primaryButtonIsClose, secondaryButtonIsClose, shouldShowFocusedAlert, silentActivationReason, coordinate, shouldCheckDistanceFromLastAlert, statsAlertId, statsType, statsSubtype, statsSubtypeTrait, statsUniqueId, dismissImmediatelyUponRemoval, isApproachingWithValidationHasValue, isApproachingWithValidation, hideActionsWhenInvalid, showOnCarPlayDashboard, doNotHideOnMapMovement);
    @try {
        Class idClass=NSClassFromString(@"Waze.CommonCodeAlertId");
        SEL selector=sel_registerName("commonCodeUniqueId");
        Method method=class_getInstanceMethod(idClass,selector);
        if (idClass && [alertId isKindOfClass:idClass] && method &&
            !strcmp(method_getTypeEncoding(method),"@16@0:8")) {
            id identifier=((id (*)(id,SEL))objc_msgSend)(alertId,selector);
            if ([identifier isKindOfClass:NSString.class]) {
                NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
                dispatch_async(dispatch_get_main_queue(), ^{
                    ObserveAlert(iconName,statsType,statsSubtype,statsSubtypeTrait,distanceMeters,isValid,didPassAlert,now);
                    [store updateIdentifier:identifier icon:iconName type:statsType subtype:statsSubtype
                        trait:statsSubtypeTrait distance:distanceMeters
                        valid:isValid passed:didPassAlert atUptime:now];
                    Publish(NO);
                });
            }
        }
    } @catch (__unused NSException *exception) {}
    return result;
}

__attribute__((constructor)) static void Start(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.waze.iphone"]) return;
    // Every native entry point below is checked on its own (selector and type encoding, or the
    // getter's code), so builds other than 5.25.0 keep whatever still matches.
    NSString *version=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    Class cls=NSClassFromString(@"third_party_waze_client_ios_modules_WazeCommonCodeAlerts_WazeCommonCodeAlerts.CommonCodeAlertDescriptorData");
    SEL selector=sel_registerName("initWithAlertId:priority:isPreemptive:isValid:distanceMeters:title:carplayTitle:alertDescription:carplayAlertDescription:iconName:isCancellable:canSendThumbsUp:isCloseOnly:primaryButtonText:secondaryButtonText:disableCompactEtaBarTaps:showDistance:keepOpenAfterAction:closeOnlyOnSelection:timeoutSeconds:timerType:zoneAlertData:shouldShowStillThere:didPassAlert:triggerDistanceMeters:primaryButtonIsClose:secondaryButtonIsClose:shouldShowFocusedAlert:silentActivationReason:coordinate:shouldCheckDistanceFromLastAlert:statsAlertId:statsType:statsSubtype:statsSubtypeTrait:statsUniqueId:dismissImmediatelyUponRemoval:isApproachingWithValidationHasValue:isApproachingWithValidation:hideActionsWhenInvalid:showOnCarPlayDashboard:doNotHideOnMapMovement:");
    Method method=class_getInstanceMethod(cls,selector);
    const char *encoding="@268@0:8@16q24B32B36q40@48@56@64@72@80B88B92B96@100@108B116B120B124B128d132q140@148B156B160q164B172B176B180q184@192B200q204q212q220q228@236B244B248B252B256B260B264";
    store=[GVMWazeOutputStore new];
    if (method && !strcmp(method_getTypeEncoding(method),encoding)) {
        MSHookMessageEx(cls,selector,(IMP)Descriptor,(IMP *)&OriginalDescriptor);
        Status([NSString stringWithFormat:@"Waze %@: output v1 alert hook active",version]);
    } else Status([NSString stringWithFormat:@"Waze %@: alert ABI mismatch; speed and limit checked independently",version]);
    notify_register_dispatch(GVMOutputRequestName(GVMSourceWaze).UTF8String,&requestToken,
        dispatch_get_main_queue(),^(__unused int token) { Publish(YES); });
    ConfigureNativeLimit();
    Class gpsClass=NSClassFromString(@"WSVLocationGPSPosition");
    SEL gpsSelector=sel_registerName("initWithLongitude:latitude:altitudeMeters:speedMMSec:steering:accuracyMeters:timeSec:hasSteering:speedAccuracyMMsec:steeringAccuracy:");
    Method gpsMethod=class_getInstanceMethod(gpsClass,gpsSelector);
    if (gpsMethod && !strcmp(method_getTypeEncoding(gpsMethod),"@92@0:8d16d24d32d40d48d56d64B72d76d84"))
        MSHookMessageEx(gpsClass,gpsSelector,(IMP)GPS,(IMP *)&OriginalGPS);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
            // iOS may deliver no GPS while stationary; Waze still holds its current limit, so
            // re-read that live native state each second as VietMap's engine re-sends it, and
            // keep a stationary speed until the next sample.
            if (GVMSelectedSourceID()==GVMSourceWaze) {
                double uptime=NSProcessInfo.processInfo.systemUptime;
                if (nativeLimitReady) [store updateLimit:ReadNativeLimit() uptime:uptime];
                [store holdStationarySpeedAtUptime:uptime now:NSDate.date.timeIntervalSince1970];
            }
            Publish(NO);
        }];
    });
}
