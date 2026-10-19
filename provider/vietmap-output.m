#import "vietmap-output.h"
#import "vietmap-alert-assets.h"
#import "source-output.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static NSDictionary<NSString *,NSNumber *> *Types(void) {
    static NSDictionary *types;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ types=@{
        @"camera_ai.png":@(GVMRoadAlertCameraAI), @"highway_rest_area.png":@(GVMRoadAlertRestArea),
        @"khu_dan_cu.png":@(GVMRoadAlertResidentialStart),
        @"residential_area_in.png":@(GVMRoadAlertResidentialStart),
        @"residential_area_out.png":@(GVMRoadAlertResidentialEnd),
        @"leftAndRightTurnOnly.png":@(GVMRoadAlertMandatoryLeftRight),
        @"leftTurnOnly.png":@(GVMRoadAlertMandatoryLeft),
        @"noEntry.png":@(GVMRoadAlertNoEntry), @"noEntryNoLeftTurn.png":@(GVMRoadAlertNoEntryLeft),
        @"noEntryNoRightTurn.png":@(GVMRoadAlertNoEntryRight), @"noLeftTurn.png":@(GVMRoadAlertNoLeft),
        @"noLeftTurnNoRightTurn.png":@(GVMRoadAlertNoLeftRight),
        @"noLeftTurnUTurn.png":@(GVMRoadAlertNoLeftUTurn), @"noRightTurn.png":@(GVMRoadAlertNoRight),
        @"noRightTurnUTurn.png":@(GVMRoadAlertNoRightUTurn), @"noUTurnLeft.png":@(GVMRoadAlertNoUTurnLeft),
        @"noUTurnRight.png":@(GVMRoadAlertNoUTurnRight), @"no_passing_in.png":@(GVMRoadAlertNoPassingStart),
        @"no_passing_out.png":@(GVMRoadAlertNoPassingEnd), @"penalty_camera.png":@(GVMRoadAlertPenaltyCamera),
        @"railway.png":@(GVMRoadAlertRailway), @"retrict_unknown.png":@(GVMRoadAlertRestriction),
        @"rightTurnOnly.png":@(GVMRoadAlertMandatoryRight), @"slow_down.png":@(GVMRoadAlertSlowDown),
        @"speed_limit_camera.png":@(GVMRoadAlertSpeedCamera), @"stop_lane.png":@(GVMRoadAlertStopLane),
        @"straightAheadOnly.png":@(GVMRoadAlertMandatoryStraight),
        @"straightAndLeftTurnOnly.png":@(GVMRoadAlertMandatoryStraightLeft),
        @"straightAndRightTurnOnly.png":@(GVMRoadAlertMandatoryStraightRight),
        @"toll.png":@(GVMRoadAlertToll), @"toll_etc.png":@(GVMRoadAlertTollETC),
        @"traffic_camera.png":@(GVMRoadAlertTrafficCamera), @"tunnel.png":@(GVMRoadAlertTunnel)
    }; });
    return types;
}
NSDictionary *GVMVietMapOutputAlert(NSDictionary *alert,NSTimeInterval receivedAt) {
    if (![alert isKindOfClass:NSDictionary.class]) return nil;
    id kind=alert[@"kind"], provider=alert[@"provider"];
    for (id number in @[kind ?: NSNull.null,provider ?: NSNull.null])
        if (![number isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)number)==CFBooleanGetTypeID() ||
            !isfinite([number doubleValue]) || [number doubleValue]<0 ||
            [number doubleValue]!=[number unsignedIntegerValue]) return nil;
    if ([provider unsignedIntegerValue]!=GVMSourceVietMap) return nil;
    NSString *name=GVMVietMapAssetName([kind unsignedIntegerValue]);
    if (!name) return nil;
    NSNumber *type=Types()[name], *value=nil;
    if ([name hasPrefix:@"speed_limit_"] && ![name isEqual:@"speed_limit_camera.png"]) {
        value=@([[name substringFromIndex:12] integerValue]); type=@(GVMRoadAlertSpeedLimit);
    } else if ([name isEqual:@"limit_80.png"]) {
        value=@80; type=@(GVMRoadAlertSpeedLimit);
    }
    if (!type) return nil;
    return @{@"type":type,@"value":value ?: NSNull.null,@"distance":alert[@"distance"] ?: NSNull.null,
        @"receivedAt":@(receivedAt)};
}
const NSTimeInterval GVMVietMapAdvanceLaneLifetime=6;
NSDictionary *GVMVietMapLaneSample(NSDictionary *advance,NSArray<NSNumber *> *codes,NSArray<NSNumber *> *limits,NSTimeInterval now) {
    if (!isfinite(now)) return nil;
    NSArray *ahead=[advance isKindOfClass:NSDictionary.class] ? advance[@"items"] : nil;
    if ([ahead isKindOfClass:NSArray.class] && ahead.count && ahead.count<=GVMMaximumLanes &&
        [advance[@"distance"] isKindOfClass:NSNumber.class])
        return @{@"distance":advance[@"distance"],@"items":ahead,@"receivedAt":@(now)};
    BOOL arrows=[codes isKindOfClass:NSArray.class] && codes.count && codes.count<=GVMMaximumLanes;
    BOOL signs=[limits isKindOfClass:NSArray.class] && limits.count && limits.count<=GVMMaximumLanes &&
        (!arrows || limits.count==codes.count);
    if (!arrows && !signs) return nil;
    NSUInteger count=arrows ? codes.count : limits.count;
    NSMutableArray *items=[NSMutableArray new];
    for (NSUInteger i=0;i<count;i++) {
        NSMutableDictionary *item=[@{@"code":arrows ? codes[i] : @0,@"enabled":@YES} mutableCopy];
        if (signs) item[@"limit"]=limits[i];
        [items addObject:[item copy]];
    }
    return @{@"distance":NSNull.null,@"items":items,@"receivedAt":@(now)};
}
NSDictionary *GVMVietMapOutput(NSDictionary *samples,NSArray<NSDictionary *> *alertEntries,NSTimeInterval now) {
    if (alertEntries && (![alertEntries isKindOfClass:NSArray.class] || alertEntries.count>64)) return nil;
    NSMutableArray *alerts=[NSMutableArray new], *active=[NSMutableArray new];
    for (NSDictionary *entry in alertEntries) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id received=entry[@"receivedAt"];
        if (![received isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)received)==CFBooleanGetTypeID()) continue;
        NSDictionary *alert=GVMVietMapOutputAlert(entry[@"sample"],[received doubleValue]);
        if (!alert) continue;
        if (![entry[@"active"] isEqual:@YES]) { [alerts addObject:alert]; continue; }
        NSMutableDictionary *inEffect=[alert mutableCopy]; inEffect[@"distance"]=NSNull.null;
        [active addObject:inEffect];
    }
    for (NSDictionary *alert in active) {
        BOOL upcoming=NO;
        for (NSDictionary *other in alerts)
            if ([other[@"type"] isEqual:alert[@"type"]] && [other[@"value"] isEqual:alert[@"value"]]) { upcoming=YES; break; }
        if (!upcoming) [alerts addObject:alert];
    }
    return GVMSourceOutput(GVMSourceVietMap,samples,alerts,now);
}
