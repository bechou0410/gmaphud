#import "test-state.h"
#include <math.h>

const char *const GVMTestStateName = "com.chou.googlemaps.vietmap.test";
const char *const GVMTestLaneStateName = "com.chou.googlemaps.vietmap.test.lanes";
const char *const GVMTestLaneLimitStateName = "com.chou.googlemaps.vietmap.test.lane-limits";
// One atomic state contains both test values and a bounded monotonic expiry.
uint64_t GVMEncodeTest(NSInteger speed, NSInteger limit, NSTimeInterval uptime, NSInteger seconds) {
    if (speed < 0 || speed > 400 || limit < 1 || limit > 400 || seconds < 1 || seconds > 300 ||
        !isfinite(uptime) || uptime < 0 || uptime + seconds >= (double)(UINT64_MAX >> 18) / 1000) return 0;
    uint64_t expiry = (uint64_t)floor((uptime + seconds) * 1000);
    return (expiry << 18) | ((uint64_t)limit << 9) | (uint64_t)speed;
}
NSDictionary *GVMDecodeTest(uint64_t state, NSTimeInterval uptime) {
    if (!state || !isfinite(uptime) || uptime < 0) return nil;
    NSInteger speed = state & 511, limit = (state >> 9) & 511;
    double remaining = (double)(state >> 18) / 1000 - uptime;
    if (speed > 400 || limit < 1 || limit > 400 || remaining <= 0 || remaining > 300) return nil;
    return @{@"speed":@(speed), @"limit":@(limit)};
}

// Bits 0-13 distance (16383 unknown), 14-16 lane count, then six bits per lane: the five known
// directions (straight, right, U-turn left, left, U-turn right) and enabled.
uint64_t GVMEncodeTestLanes(NSArray<NSDictionary *> *items, id distance) {
    if (![items isKindOfClass:NSArray.class] || !items.count || items.count>7) return 0;
    uint64_t meters=16383;
    if (distance && distance!=NSNull.null) {
        if (![distance isKindOfClass:NSNumber.class] || [distance doubleValue]<0 || [distance doubleValue]>10000 ||
            floor([distance doubleValue])!=[distance doubleValue]) return 0;
        meters=[distance unsignedLongLongValue];
    }
    uint64_t state=meters | ((uint64_t)items.count<<14);
    for (NSUInteger i=0;i<items.count;i++) {
        id code=[items[i] isKindOfClass:NSDictionary.class] ? items[i][@"code"] : nil;
        if (![code isKindOfClass:NSNumber.class] || [code integerValue]<0 || [code integerValue]>511) return 0;
        NSUInteger c=[code unsignedIntegerValue];
        uint64_t bits=(c&1) | ((c>>1)&2) | ((c>>2)&4) | ((c>>3)&8) | ((c>>4)&16) |
            ([items[i][@"enabled"] isEqual:@NO] ? 0 : 32);
        state|=bits<<(17+6*i);
    }
    return state;
}
NSDictionary *GVMDecodeTestLanes(uint64_t state) {
    NSUInteger count=(state>>14)&7, meters=state&16383;
    if (!count || (meters>10000 && meters!=16383) || state>>(17+6*count)) return nil;
    NSMutableArray *items=[NSMutableArray new];
    for (NSUInteger i=0;i<count;i++) {
        uint64_t bits=(state>>(17+6*i))&63;
        NSUInteger code=(NSUInteger)((bits&1) | ((bits&2)<<1) | ((bits&4)<<2) | ((bits&8)<<3) | ((bits&16)<<4));
        [items addObject:@{@"code":@(code),@"enabled":@((BOOL)((bits&32)!=0))}];
    }
    return @{@"distance":meters==16383 ? NSNull.null : @(meters),@"items":items};
}
// Bit 63 marks a set, then nine bits per lane: the sign and the size of the limit.
uint64_t GVMEncodeTestLaneLimits(NSArray<NSDictionary *> *items) {
    if (![items isKindOfClass:NSArray.class] || !items.count || items.count>7) return 0;
    uint64_t state=1ULL<<63;
    for (NSUInteger i=0;i<items.count;i++) {
        id limit=[items[i] isKindOfClass:NSDictionary.class] ? items[i][@"limit"] : nil;
        if (![limit isKindOfClass:NSNumber.class] || [limit integerValue]<-255 || [limit integerValue]>255) return 0;
        NSInteger value=[limit integerValue];
        state|=((uint64_t)(value<0 ? 256 : 0) | (uint64_t)labs(value))<<(9*i);
    }
    return state;
}
NSArray<NSNumber *> *GVMDecodeTestLaneLimits(uint64_t state, NSUInteger count) {
    if (!(state>>63) || !count || count>7 || (state&~(1ULL<<63))>>(9*count)) return nil;
    NSMutableArray *limits=[NSMutableArray new];
    for (NSUInteger i=0;i<count;i++) {
        uint64_t bits=(state>>(9*i))&511;
        [limits addObject:@(bits&256 ? -(NSInteger)(bits&255) : (NSInteger)bits)];
    }
    return limits;
}
NSDictionary *GVMParseTestLanes(NSString *text) {
    NSArray<NSString *> *parts=[text componentsSeparatedByString:@"@"];
    if (!parts.count || parts.count>2) return nil;
    id distance=NSNull.null;
    NSCharacterSet *digits=NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    if (parts.count==2) {
        if (!parts[1].length || parts[1].length>5 || [parts[1] rangeOfCharacterFromSet:digits].location!=NSNotFound) return nil;
        distance=@(parts[1].integerValue);
    }
    NSMutableArray *items=[NSMutableArray new];
    NSUInteger limited=0;
    for (NSString *lane in [parts[0] componentsSeparatedByString:@","]) {
        NSArray<NSString *> *fields=[lane componentsSeparatedByString:@":"];
        if (fields.count>2) return nil;
        BOOL disabled=[fields[0] hasPrefix:@"x"];
        NSString *code=disabled ? [fields[0] substringFromIndex:1] : fields[0];
        if (!code.length || code.length>3 || [code rangeOfCharacterFromSet:digits].location!=NSNotFound || code.integerValue>511) return nil;
        NSMutableDictionary *item=[@{@"code":@(code.integerValue),@"enabled":@(!disabled)} mutableCopy];
        if (fields.count==2) {
            NSString *limit=[fields[1] hasPrefix:@"-"] ? [fields[1] substringFromIndex:1] : fields[1];
            if (!limit.length || limit.length>3 || [limit rangeOfCharacterFromSet:digits].location!=NSNotFound ||
                limit.integerValue>255) return nil;
            item[@"limit"]=@(fields[1].integerValue);
            limited++;
        }
        [items addObject:[item copy]];
    }
    if (limited && limited!=items.count) return nil;
    return GVMEncodeTestLanes(items,distance) ? @{@"distance":distance,@"items":items} : nil;
}
