#import "test-state.h"
#include <math.h>

const char *const GVMTestStateName = "com.chou.googlemaps.vietmap.test";
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
