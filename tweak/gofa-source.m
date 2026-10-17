#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <notify.h>
#import "source-transport.h"
#import "source-output.h"
#import "background-location.h"
#include "gofa-alert-policy.h"
#include <math.h>
extern void *GVMGofaPayload(const void *);
static NSMutableDictionary *samples;
static NSNumber *boardLimit;
static CLLocation *boardAnchor;
static double boardReceived=-1;
static NSMutableDictionary *candidateGroups, *candidateTimes;
static NSMutableSet *passedPoints, *passedLaneBoards;
// GOFA's lane board ahead (identity, lanes text, where it stands) and when GOFA last posted it.
static NSDictionary *laneBoard;
static double laneBoardReceived=-1;
static CLLocation *position;
static double positionTime=-1, lastGPSUnixTime=-1;
static int requestToken=-1;
static NSInteger authorization=-1;
static BOOL backgroundLocation;
static NSArray *PointKey(NSDictionary *point) {
    return @[point[@"identity"],point[@"sign"],point[@"latitude"],point[@"longitude"]];
}
// Latest fresh GPS position when the native board was processed; nil when none was fresh.
static CLLocation *FreshAnchor(void) {
    double age=NSProcessInfo.processInfo.systemUptime-positionTime;
    return age>=0 && age<5 ? position : nil;
}
static double AnchorDistance(CLLocation *anchor) {
    return position && anchor ? [position distanceFromLocation:anchor] : NAN;
}
static void (*originalLocations)(id,SEL,CLLocationManager *,NSArray *);
static NSUInteger Semantic(NSInteger sign) {
    // GOFA 4.2.1 enum reflection records and rawValue getter tables, measured in this build.
    switch (sign) {
        case 33:return GVMRoadAlertSpeedCamera;
        case 32:return GVMRoadAlertTrafficCamera;
        case 34:return GVMRoadAlertRedLightCamera;
        case 36:return GVMRoadAlertCameraAI;
        case 12:return GVMRoadAlertResidentialStart;
        case 13:return GVMRoadAlertResidentialEnd;
        case 18:return GVMRoadAlertToll;
        case 14:return GVMRoadAlertNoPassingStart;
        case 15:return GVMRoadAlertNoPassingEnd;
        case 17:return GVMRoadAlertRestArea;
        case 21:return GVMRoadAlertNoLeft;
        case 22:return GVMRoadAlertNoRight;
        case 23:return GVMRoadAlertNoLeftUTurn;
        case 24:return GVMRoadAlertNoRightUTurn;
        case 25:return GVMRoadAlertNoUTurnLeft;
        case 26:return GVMRoadAlertNoUTurnRight;
        default:return 0;
    }
}
static void Publish(BOOL force) {
    GVMRefreshLocationSession();
    double now=NSProcessInfo.processInfo.systemUptime;
    // GOFA's latest board remains its displayed limit, including while iOS delivers no GPS,
    // until GOFA replaces or clears it or the latest GPS lies away from where it was observed.
    if (boardLimit && GVMGofaBoardNear(AnchorDistance(boardAnchor)))
        samples[@"speedLimit"]=@{@"value":boardLimit,@"receivedAt":@(now)};
    else if (boardLimit && boardAnchor) [samples removeObjectForKey:@"speedLimit"];
    NSMutableArray *alerts=NSMutableArray.array;
    NSMutableSet *membership=NSMutableSet.set;
    for (NSString *group in candidateGroups) {
        double age=now-[candidateTimes[group] doubleValue];
        if (age>=0 && age<5) for (NSDictionary *point in candidateGroups[group])
            [membership addObject:PointKey(point)];
    }
    // Keep suppression across groups/notifications, release after native removal or expiry.
    [passedPoints intersectSet:membership];
    if (position && now-positionTime>=0 && now-positionTime<5) {
      for (NSString *group in candidateGroups) {
        double candidateTime=[candidateTimes[group] doubleValue];
        if (now-candidateTime<0 || now-candidateTime>=5) continue;
        for (NSDictionary *point in candidateGroups[group]) {
            NSUInteger type=Semantic([point[@"sign"] integerValue]); if (!type) continue;
            CLLocation *target=[[CLLocation alloc] initWithLatitude:[point[@"latitude"] doubleValue] longitude:[point[@"longitude"] doubleValue]];
            double distance=[position distanceFromLocation:target];
            NSArray *key=PointKey(point);
            if (GVMGofaPointPassed([passedPoints containsObject:key],distance)) {
                [passedPoints addObject:key]; continue;
            }
            if (!isfinite(distance) || distance>10000) continue;
            [alerts addObject:@{@"type":@(type),@"value":NSNull.null,@"distance":@(llround(distance)),@"receivedAt":@(MIN(positionTime,candidateTime))}];
        }
      }
    }
    // The lane board ahead: its lanes with the distance to it, until it is reached or GOFA clears it.
    [samples removeObjectForKey:@"lanes"];
    BOOL boardCurrent=laneBoard && now-laneBoardReceived>=0 && now-laneBoardReceived<3;
    if (!boardCurrent) [passedLaneBoards removeAllObjects];
    else if (position && now-positionTime>=0 && now-positionTime<5) {
        id key=laneBoard[@"identity"];
        [passedLaneBoards intersectSet:[NSSet setWithObject:key]];
        CLLocation *target=[[CLLocation alloc] initWithLatitude:[laneBoard[@"latitude"] doubleValue] longitude:[laneBoard[@"longitude"] doubleValue]];
        double distance=[position distanceFromLocation:target];
        unsigned codes[GVMMaximumLanes];
        unsigned count=GVMGofaLaneCodes([laneBoard[@"lanes"] UTF8String],codes,GVMMaximumLanes);
        if (GVMGofaPointPassed([passedLaneBoards containsObject:key],distance)) [passedLaneBoards addObject:key];
        else if (count && isfinite(distance) && distance<=10000) {
            NSMutableArray *items=NSMutableArray.array;
            for (unsigned i=0;i<count;i++) [items addObject:@{@"code":@(codes[i]),@"enabled":@YES}];
            samples[@"lanes"]=@{@"distance":@(llround(distance)),@"items":items,@"receivedAt":@(now)};
        }
    }
    NSDictionary *output=GVMSourceOutput(GVMSourceGofa,samples,alerts,now);
    GVMPublishSourceOutput(output,now,force);
    static double lastStatus=-1;
    if (lastStatus<0 || now-lastStatus>=1) {
        lastStatus=now;
        NSMutableDictionary *status=[output mutableCopy]; status[@"appState"]=@(UIApplication.sharedApplication.applicationState);
        status[@"authorization"]=@(authorization); status[@"backgroundLocation"]=@(backgroundLocation);
        status[@"gpsAge"]=positionTime>=0 ? @(now-positionTime) : NSNull.null;
        NSData *data=[NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
        [data writeToFile:[NSTemporaryDirectory() stringByAppendingPathComponent:@"gmaphud-gofa-output.json"] atomically:YES];
    }
}
static void Locations(id self,SEL cmd,CLLocationManager *manager,NSArray *locations) {
    originalLocations(self,cmd,manager,locations);
    id latest=locations.lastObject;
    if (![latest isKindOfClass:CLLocation.class]) return;
    CLLocation *location=latest;
    double age=-location.timestamp.timeIntervalSinceNow;
    double receipt=NSProcessInfo.processInfo.systemUptime;
    if (!isfinite(age) || age<0 || age>=5 || location.horizontalAccuracy<0 ||
        !CLLocationCoordinate2DIsValid(location.coordinate)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        double timestamp=receipt-age;
        double nativeTime=location.timestamp.timeIntervalSince1970;
        if (nativeTime<=lastGPSUnixTime || timestamp<=positionTime) return;
        lastGPSUnixTime=nativeTime;
        position=location; positionTime=timestamp;
        authorization=manager.authorizationStatus; backgroundLocation=manager.allowsBackgroundLocationUpdates;
        // This is GOFA's GPS input in m/s, independent of its configurable display offset.
        double speed=location.speed;
        if (isfinite(speed) && speed>=0 && speed*3.6<=400) samples[@"speed"]=@{@"value":@(llround(speed*3.6)),@"receivedAt":@(timestamp)};
        else [samples removeObjectForKey:@"speed"];
        // A board processed before any fresh fix is anchored to the first fix within its TTL.
        double now=NSProcessInfo.processInfo.systemUptime;
        if (boardLimit && !boardAnchor && now-boardReceived>=0 && now-boardReceived<5) boardAnchor=location;
        Publish(NO);
    });
}
__attribute__((constructor)) static void Initialize(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.lumi.GOFA"]) return;
    if (![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"4.2.1"] ||
        ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"3"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        samples=NSMutableDictionary.dictionary; candidateGroups=NSMutableDictionary.dictionary;
        candidateTimes=NSMutableDictionary.dictionary;
        passedPoints=NSMutableSet.set; passedLaneBoards=NSMutableSet.set;
        Class cls=NSClassFromString(@"GOFA.GofaLocationManager");
        SEL selector=@selector(locationManager:didUpdateLocations:);
        Method method=class_getInstanceMethod(cls,selector);
        if (method && !strcmp(method_getTypeEncoding(method),"v32@0:8@16@24")) MSHookMessageEx(cls,selector,(IMP)Locations,(IMP *)&originalLocations);
        for (NSString *name in @[@"notificationSpeedBoard",@"notificationNextBoard",@"notificationOtherBoard",@"notificationLaneBoards"]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                double received=NSProcessInfo.processInfo.systemUptime;
                void *raw=GVMGofaPayload((__bridge const void *)note);
                NSDictionary *payload=CFBridgingRelease(raw);
                if (!payload) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (payload[@"laneBoard"]) {
                        if (received<laneBoardReceived) return;
                        laneBoardReceived=received;
                        laneBoard=[payload[@"laneBoard"] isKindOfClass:NSDictionary.class] ? payload[@"laneBoard"] : nil;
                    }
                    else if (payload[@"candidates"]) {
                        NSString *group=payload[@"candidateGroup"];
                        if (candidateTimes[group] && received<[candidateTimes[group] doubleValue]) return;
                        candidateGroups[group]=payload[@"candidates"]; candidateTimes[group]=@(received);
                    }
                    else {
                        if (received<boardReceived) return;
                        boardReceived=received;
                        id value=payload[@"speedLimit"];
                        if ([value isKindOfClass:NSNumber.class] && [value integerValue]>0 && [value integerValue]<=400) {
                            boardLimit=value; boardAnchor=FreshAnchor();
                            samples[@"speedLimit"]=@{@"value":value,@"receivedAt":@(received)};
                        } else {
                            // An unknown or zero native board clears the limit.
                            boardLimit=nil; boardAnchor=nil;
                            [samples removeObjectForKey:@"speedLimit"];
                        }
                    }
                    Publish(NO);
                });
            }];
        }
        notify_register_dispatch(GVMOutputRequestName(GVMSourceGofa).UTF8String,&requestToken,dispatch_get_main_queue(),^(int token){ (void)token; Publish(YES); });
        Publish(YES);
        // Hold the native board and release a vanished host's lease while GPS is silent.
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
            Publish(NO);
        }];
    });
}
