#import "speed-state.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

const char *const GVMSpeedStateName = "com.chou.googlemaps.vietmap.speed";
const char *const GVMLimitStateName = "com.chou.googlemaps.vietmap.limit";

// Each independent field carries its original monotonic sample time, not a heartbeat time.
uint64_t GVMEncodeSample(NSNumber *value, NSTimeInterval receivedAt) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return 0;
    double number = value.doubleValue;
    if (!isfinite(number) || number < 0 || number > 400 || floor(number) != number ||
        !isfinite(receivedAt) || receivedAt < 0 || receivedAt >= (double)(UINT64_MAX >> 10) / 1000) return 0;
    return ((uint64_t)floor(receivedAt * 1000) << 10) | 512 | (uint64_t)number;
}

NSNumber *GVMDecodeSample(uint64_t state, NSTimeInterval uptime, BOOL allowZero) {
    if (!(state & 512) || !isfinite(uptime) || uptime < 0) return nil;
    uint64_t value = state & 511;
    if (value > 400 || (!allowZero && value == 0)) return nil;
    double age = uptime - (double)(state >> 10) / 1000;
    if (!isfinite(age) || age < 0 || age >= 5) return nil;
    return @(value);
}
