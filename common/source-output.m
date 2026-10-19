#import "source-output.h"
#import "speed-state.h"
#import "alert-state.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#include <string.h>

static BOOL Integer(id value, double minimum, double maximum) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID()) return NO;
    double number=[value doubleValue];
    return isfinite(number) && number>=minimum && number<=maximum && floor(number)==number;
}
static BOOL BooleanValue(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID();
}
static BOOL Fresh(id received, double now) {
    if (![received isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)received)==CFBooleanGetTypeID()) return NO;
    double time=[received doubleValue], age=now-time;
    return isfinite(now) && now>=0 && isfinite(time) && time>=0 && age>=0 && age<5;
}
BOOL GVMSourceIDValid(NSUInteger sourceID) { return sourceID>=1 && sourceID<=GVMMaximumSourceID; }
NSString *GVMSourceDisplayName(NSUInteger sourceID) {
    return sourceID==GVMSourceVietMap ? @"VietMap Live" : sourceID==GVMSourceWaze ? @"Waze" : sourceID==GVMSourceGofa ? @"GOFA" : @"GMapHUD";
}
NSString *GVMRoadAlertName(NSUInteger type) {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ names=@[@"camera-ai",@"rest-area",@"residential-start",@"speed-limit",
        @"no-entry",@"no-entry-left",@"no-entry-right",@"no-left",@"no-left-right",@"no-left-u-turn",
        @"no-right",@"no-right-u-turn",@"no-u-turn-left",@"no-u-turn-right",@"no-passing-start",
        @"no-passing-end",@"penalty-camera",@"railway",@"residential-end",@"restriction",
        @"mandatory-right",@"slow-down",@"speed-camera",@"stop-lane",@"mandatory-straight",
        @"mandatory-straight-left",@"mandatory-straight-right",@"toll",@"toll-etc",@"traffic-camera",
        @"tunnel",@"mandatory-left-right",@"mandatory-left",@"red-light-camera",@"accident",@"accident-minor",@"animal",@"assistance",@"bad-weather",@"blocked-lane",@"both-shoulders-ending",@"bus-lane-cam",@"closed-lane-construction",@"closed-lane-crash",@"closure",@"cyclist",@"dangerous-curves",@"dangerous-intersection",@"distance-between-vehicles-camera",@"dummy-camera",@"emergency-vehicle",@"fork",@"hazard",@"hazard-animals",@"hazard-broken-light",@"hazard-construction",@"hazard-object-on-road",@"hazard-pothole",@"hazard-roadkill",@"hazard-stopped",@"hazard-weather-flood",@"hazard-weather-fog",@"hazard-weather-hail",@"hazard-weather-ice",@"hazard-weather-snow",@"hazardonroad",@"highway-crosswalk",@"hov-camera",@"intersection",@"lanes-merging",@"left-lane-ending",@"left-shoulder-ending",@"merge",@"narrow-bridge",@"noise-camera",@"phone-camera",@"police",@"police-mobile-camera",@"raised-crosswalk",@"red-light-and-speed-camera",@"right-lane-ending",@"right-shoulder-ending",@"school-zone",@"seatbelt-camera",@"slippery-road",@"speed-bumps",@"stop-sign-camera",@"topes"]; });
    return type>=1 && type<=names.count ? names[type-1] : nil;
}
NSString *GVMRoadAlertIconName(NSUInteger type, NSNumber *value) {
    if (type==GVMRoadAlertSpeedLimit) {
        if (![value isKindOfClass:NSNumber.class] || !Integer(value,1,400)) return nil;
        NSUInteger limit=value.unsignedIntegerValue;
        return ((limit>=10 && limit<=120 && limit%10==0) || limit==5 || limit==15 || limit==25 || limit==35 || limit==45) ?
            [NSString stringWithFormat:@"speed_limit_%lu.png",(unsigned long)limit] : nil;
    }
    static NSArray<NSString *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ icons=@[@"camera_ai.png",@"highway_rest_area.png",@"residential_area_in.png",@"",
        @"noEntry.png",@"noEntryNoLeftTurn.png",@"noEntryNoRightTurn.png",@"noLeftTurn.png",@"noLeftTurnNoRightTurn.png",
        @"noLeftTurnUTurn.png",@"noRightTurn.png",@"noRightTurnUTurn.png",@"noUTurnLeft.png",@"noUTurnRight.png",
        @"no_passing_in.png",@"no_passing_out.png",@"penalty_camera.png",@"railway.png",@"residential_area_out.png",
        @"retrict_unknown.png",@"rightTurnOnly.png",@"slow_down.png",@"speed_limit_camera.png",@"stop_lane.png",
        @"straightAheadOnly.png",@"straightAndLeftTurnOnly.png",@"straightAndRightTurnOnly.png",@"toll.png",@"toll_etc.png",
        @"traffic_camera.png",@"tunnel.png",@"leftAndRightTurnOnly.png",@"leftTurnOnly.png",@"traffic_camera.png",@"accident.png",@"accident-minor.png",@"animal.png",@"assistance.png",@"bad-weather.png",@"blocked-lane.png",@"both-shoulders-ending.png",@"bus-lane-cam.png",@"closed-lane-construction.png",@"closed-lane-crash.png",@"closure.png",@"cyclist.png",@"dangerous-curves.png",@"dangerous-intersection.png",@"distance-between-vehicles-camera.png",@"dummy-camera.png",@"emergency-vehicle.png",@"fork.png",@"hazard.png",@"hazard-animals.png",@"hazard-broken-light.png",@"hazard-construction.png",@"hazard-object-on-road.png",@"hazard-pothole.png",@"hazard-roadkill.png",@"hazard-stopped.png",@"hazard-weather-flood.png",@"hazard-weather-fog.png",@"hazard-weather-hail.png",@"hazard-weather-ice.png",@"hazard-weather-snow.png",@"hazardonroad.png",@"highway-crosswalk.png",@"hov-camera.png",@"intersection.png",@"lanes-merging.png",@"left-lane-ending.png",@"left-shoulder-ending.png",@"merge.png",@"narrow-bridge.png",@"noise-camera.png",@"phone-camera.png",@"police.png",@"police-mobile-camera.png",@"raised-crosswalk.png",@"red-light-and-speed-camera.png",@"right-lane-ending.png",@"right-shoulder-ending.png",@"school-zone.png",@"seatbelt-camera.png",@"slippery-road.png",@"speed-bumps.png",@"stop-sign-camera.png",@"topes.png"]; });
    return type>=1 && type<=icons.count ? icons[type-1] : nil;
}
static NSDictionary *Sample(id sample, BOOL allowZero, double now) {
    if (![sample isKindOfClass:NSDictionary.class] || !Fresh(sample[@"receivedAt"],now) ||
        !Integer(sample[@"value"],allowZero ? 0 : 1,400) ||
        !GVMEncodeSample(sample[@"value"],[sample[@"receivedAt"] doubleValue])) return nil;
    return @{@"value":sample[@"value"],@"receivedAt":sample[@"receivedAt"]};
}
// One lane set for the next junction. All lanes or none: a malformed lane rejects the set.
static NSDictionary *Lanes(id lanes, double now) {
    if (![lanes isKindOfClass:NSDictionary.class] || !Fresh(lanes[@"receivedAt"],now) ||
        [lanes[@"receivedAt"] doubleValue]>=(double)(UINT64_MAX>>24)/1000) return nil;
    id items=lanes[@"items"], distance=lanes[@"distance"] ?: NSNull.null;
    if (![items isKindOfClass:NSArray.class] || ![items count] || [items count]>GVMMaximumLanes ||
        (distance!=NSNull.null && !Integer(distance,0,10000))) return nil;
    NSMutableArray *normalized=[NSMutableArray new];
    NSUInteger limited=0;
    BOOL limitsValid=YES;
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class] || !Integer(item[@"code"],0,511)) return nil;
        id enabled=item[@"enabled"] ?: @YES, limit=item[@"limit"];
        if (!BooleanValue(enabled)) return nil;
        if (limit && !Integer(limit,-255,255)) limitsValid=NO;
        if (limit) limited++;
        [normalized addObject:@{@"code":@([item[@"code"] unsignedIntegerValue]&GVMLaneKnownDirections),
            @"enabled":@([enabled boolValue])}];
    }
    // Speed limits come for every lane or for none; a partial or unreadable set is left out.
    if (limited && limitsValid && limited==normalized.count)
        for (NSUInteger i=0;i<normalized.count;i++) {
            NSMutableDictionary *lane=[normalized[i] mutableCopy];
            lane[@"limit"]=@([items[i][@"limit"] integerValue]);
            normalized[i]=[lane copy];
        }
    return @{@"distance":distance,@"items":[normalized copy],@"receivedAt":lanes[@"receivedAt"]};
}
// Five direction bits per lane on the wire, in bitmask order.
static uint64_t LaneBits(NSUInteger code) {
    return (code&1) | ((code>>1)&2) | ((code>>2)&4) | ((code>>3)&8) | ((code>>4)&16);
}
static NSUInteger LaneCode(uint64_t bits) {
    return (NSUInteger)((bits&1) | ((bits&2)<<1) | ((bits&4)<<2) | ((bits&8)<<3) | ((bits&16)<<4));
}
static NSDictionary *Alert(id alert, NSUInteger sourceID, double now) {
    if (![alert isKindOfClass:NSDictionary.class] ||
        !Integer(alert[@"type"],1,GVMRoadAlertTopes) || !Fresh(alert[@"receivedAt"],now)) return nil;
    NSUInteger type=[alert[@"type"] unsignedIntegerValue];
    id value=alert[@"value"] ?: NSNull.null, distance=alert[@"distance"] ?: NSNull.null;
    id artwork=alert[@"artworkID"] ?: @0;
    if (type==GVMRoadAlertSpeedLimit ? !Integer(value,1,400) : value!=NSNull.null) return nil;
    if ((distance!=NSNull.null && !Integer(distance,0,10000)) || !Integer(artwork,0,127)) return nil;
    if (!GVMEncodeAlert(@{@"provider":@(sourceID),@"kind":@(type),@"distance":distance},
        [alert[@"receivedAt"] doubleValue])) return nil;
    return @{@"type":@(type),@"value":value,@"distance":distance,
        @"artworkID":artwork,@"receivedAt":alert[@"receivedAt"]};
}
NSDictionary *GVMNormalizeSourceOutput(id output, NSTimeInterval now) {
    if (![output isKindOfClass:NSDictionary.class] || !Integer(output[@"schemaVersion"],1,1) ||
        !Integer(output[@"sourceID"],1,GVMMaximumSourceID) || !isfinite(now) || now<0 ||
        ![output[@"alerts"] isKindOfClass:NSArray.class] || [output[@"alerts"] count]>64) return nil;
    NSUInteger sourceID=[output[@"sourceID"] unsignedIntegerValue];
    NSMutableDictionary *normalized=[@{@"schemaVersion":@1,@"sourceID":@(sourceID)} mutableCopy];
    for (NSString *key in @[@"speed",@"speedLimit"]) {
        NSDictionary *sample=Sample(output[key],[key isEqual:@"speed"],now);
        if (sample) normalized[key]=sample;
    }
    NSMutableArray *alerts=[NSMutableArray new];
    for (id item in output[@"alerts"]) {
        NSDictionary *alert=Alert(item,sourceID,now);
        if (alert) [alerts addObject:alert];
    }
    [alerts sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        id da=a[@"distance"], db=b[@"distance"];
        if (da!=NSNull.null && db!=NSNull.null) {
            NSComparisonResult order=[da compare:db];
            if (order!=NSOrderedSame) return order;
        } else if (da!=db) return da==NSNull.null ? NSOrderedDescending : NSOrderedAscending;
        return [b[@"receivedAt"] compare:a[@"receivedAt"]];
    }];
    NSMutableArray *selected=[NSMutableArray new];
    for (NSDictionary *alert in alerts) {
        BOOL duplicate=NO;
        for (NSDictionary *prior in selected) {
            if ([prior[@"type"] isEqual:alert[@"type"]] && [prior[@"value"] isEqual:alert[@"value"]] &&
                [prior[@"distance"] isEqual:alert[@"distance"]]) { duplicate=YES; break; }
        }
        if (!duplicate) [selected addObject:alert];
        if (selected.count==2) break;
    }
    normalized[@"alerts"]=[selected copy];
    NSDictionary *lanes=Lanes(output[@"lanes"],now);
    if (lanes) normalized[@"lanes"]=lanes;
    return [normalized copy];
}
NSDictionary *GVMSourceOutput(NSUInteger sourceID, NSDictionary *samples, NSArray *alerts, NSTimeInterval now) {
    if (samples && ![samples isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *output=[@{@"schemaVersion":@1,@"sourceID":@(sourceID),@"alerts":alerts ?: @[]} mutableCopy];
    for (NSString *key in @[@"speed",@"speedLimit",@"lanes"]) if (samples[key]) output[key]=samples[key];
    return GVMNormalizeSourceOutput(output,now);
}
BOOL GVMEncodeSourceOutput(NSDictionary *output, NSTimeInterval now, GVMOutputWords *words) {
    if (!words) return NO;
    memset(words,0,sizeof(*words));
    NSDictionary *normalized=GVMNormalizeSourceOutput(output,now);
    if (!normalized) return NO;
    NSUInteger sourceID=[normalized[@"sourceID"] unsignedIntegerValue];
    for (NSUInteger i=0;i<2;i++) {
        NSDictionary *sample=normalized[i ? @"speedLimit" : @"speed"];
        words->words[i]=GVMEncodeSample(sample[@"value"],[sample[@"receivedAt"] doubleValue]);
    }
    NSArray *alerts=normalized[@"alerts"];
    for (NSUInteger i=0;i<alerts.count;i++) {
        NSDictionary *alert=alerts[i];
        words->words[2+2*i]=GVMEncodeAlert(@{@"provider":@(sourceID),@"kind":alert[@"type"],@"distance":alert[@"distance"]},[alert[@"receivedAt"] doubleValue]);
        id value=alert[@"value"];
        words->words[3+2*i]=([alert[@"artworkID"] unsignedLongLongValue]<<10) |
            (value==NSNull.null ? 0 : 512 | [value unsignedLongLongValue]);
    }
    // Lanes: receive time, count and distance (16383 when unknown), then one byte per lane:
    // five direction bits and the enabled bit, eight lanes to a word.
    NSDictionary *lanes=normalized[@"lanes"];
    if (lanes) {
        NSArray *items=lanes[@"items"];
        id meters=lanes[@"distance"];
        words->words[6]=((uint64_t)floor([lanes[@"receivedAt"] doubleValue]*1000)<<24) |
            ((uint64_t)items.count<<14) | (meters==NSNull.null ? 16383 : [meters unsignedLongLongValue]);
        for (NSUInteger i=0;i<items.count;i++)
            words->words[7+i/8]|=(LaneBits([items[i][@"code"] unsignedIntegerValue]) |
                ([items[i][@"enabled"] boolValue] ? 32 : 0))<<(8*(i%8));
        // Per-lane speed limits: ten bits a lane, six lanes to a word: present, dimmed, then the
        // number shown (0 for a sign without one).
        for (NSUInteger i=0;i<items.count;i++) {
            id limit=items[i][@"limit"];
            if (!limit) continue;
            NSInteger value=[limit integerValue];
            uint64_t number=(uint64_t)(value>=1 ? value : value<=-2 ? -value : 0);
            words->words[9+i/6]|=(512 | (value<=-2 ? 256 : 0) | number)<<(10*(i%6));
        }
    }
    return YES;
}
NSDictionary *GVMDecodeSourceOutput(NSUInteger sourceID, GVMOutputWords words, NSTimeInterval now) {
    if (!GVMSourceIDValid(sourceID)) return nil;
    NSMutableDictionary *samples=[NSMutableDictionary new];
    for (NSUInteger i=0;i<2;i++) {
        NSNumber *value=GVMDecodeSample(words.words[i],now,i==0);
        if (value) samples[i ? @"speedLimit" : @"speed"]=@{@"value":value,@"receivedAt":@((double)(words.words[i]>>10)/1000)};
    }
    NSMutableArray *alerts=[NSMutableArray new];
    for (NSUInteger i=0;i<2;i++) {
        uint64_t state=words.words[2+2*i], parameter=words.words[3+2*i];
        NSDictionary *alert=GVMDecodeAlert(state,now);
        if (!alert || [alert[@"provider"] unsignedIntegerValue]!=sourceID || parameter>>17 ||
            (!(parameter&512) && (parameter&511))) continue;
        [alerts addObject:@{@"type":alert[@"kind"],@"distance":alert[@"distance"],
            @"value":parameter&512 ? @(parameter&511) : NSNull.null,
            @"artworkID":@(parameter>>10),@"receivedAt":@((double)(state>>24)/1000)}];
    }
    uint64_t header=words.words[6];
    NSUInteger count=(header>>14)&1023, meters=header&16383;
    BOOL lanesValid=header && count>=1 && count<=GVMMaximumLanes && (meters<=10000 || meters==16383);
    NSMutableArray *items=[NSMutableArray new];
    for (NSUInteger i=0;lanesValid && i<16;i++) {
        uint64_t lane=(words.words[7+i/8]>>(8*(i%8)))&255;
        if (i>=count) { if (lane) lanesValid=NO; continue; }
        if (lane&192) { lanesValid=NO; continue; }
        [items addObject:@{@"code":@(LaneCode(lane&31)),@"enabled":@((BOOL)((lane&32)!=0))}];
    }
    // Per-lane speed limits: all lanes or none, nothing past the last lane.
    BOOL limitsValid=lanesValid && !(words.words[9]>>60) && !(words.words[10]>>60);
    NSUInteger limited=0;
    for (NSUInteger i=0;limitsValid && i<12;i++) {
        uint64_t field=(words.words[9+i/6]>>(10*(i%6)))&1023;
        if (i>=count) { if (field) limitsValid=NO; continue; }
        if (!(field&512)) { if (field) limitsValid=NO; continue; }
        NSInteger number=(NSInteger)(field&255);
        NSMutableDictionary *lane=[items[i] mutableCopy];
        lane[@"limit"]=@(field&256 ? -number : number);
        items[i]=[lane copy];
        limited++;
    }
    if (lanesValid && limited && (!limitsValid || limited!=count))
        for (NSUInteger i=0;i<count;i++) items[i]=@{@"code":items[i][@"code"],@"enabled":items[i][@"enabled"]};
    if (lanesValid) samples[@"lanes"]=@{@"distance":meters==16383 ? NSNull.null : @(meters),@"items":items,
        @"receivedAt":@((double)(header>>24)/1000)};
    return GVMSourceOutput(sourceID,samples,alerts,now);
}
NSUInteger GVMSourceIDForSelection(uint64_t selection) { return selection ? selection&7 : GVMSourceVietMap; }
BOOL GVMOutputFrameReadable(uint64_t before,uint64_t after,uint64_t selectionBefore,
    uint64_t selectionAfter,uint64_t frameSelection,NSUInteger sourceID) {
    return before==after && (before&255)==GVMOutputSchemaVersion && (before>>8)>0 &&
        !((before>>8)&1) && selectionBefore==selectionAfter && frameSelection==selectionBefore &&
        GVMSourceIDValid(sourceID) && sourceID==GVMSourceIDForSelection(selectionBefore);
}
