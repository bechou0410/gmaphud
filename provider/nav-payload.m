#import "nav-payload.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

static NSNumber *SpeedValue(id value, BOOL allowZero) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    double speed = [value doubleValue];
    if (!isfinite(speed) || speed < 0 || speed > 400 || (!allowZero && speed == 0)) return nil;
    long rounded = lround(speed);
    return (!allowZero && rounded == 0) ? nil : @(rounded);
}

NSDictionary *VMNavPayload(NSDictionary *sample, NSTimeInterval age, NSTimeInterval timestamp) {
    // TrueDash 1.0.0's scanner requires v=2; its embedded help still says v=1.
    NSMutableDictionary *payload = [@{@"v": @2, @"provider": @"vn.vietmap.live",
        @"providerName": @"VietMap Live", @"timestamp": @(timestamp)} mutableCopy];
    // A heartbeat must not renew a sample that the source has stopped updating.
    if (!isfinite(age) || age < 0 || age >= 5 || ![sample isKindOfClass:NSDictionary.class]) return payload;
    NSNumber *limit = SpeedValue(sample[@"speedLimit"], NO);
    NSNumber *speed = SpeedValue(sample[@"speed"], YES);
    if (limit) payload[@"speedLimit"] = limit;
    if (speed) payload[@"currentSpeed"] = speed;
    return payload;
}
