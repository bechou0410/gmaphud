#import "speed-state.h"
#import "nav-source.h"

static void Require(BOOL condition, NSString *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
}

int main(void) { @autoreleasepool {
    VMNavSource *source = [VMNavSource new];
    [source applyArguments:@[@{@"speed":@0, @"speedLimit":@50}, @YES] receivedAt:100];
    NSDictionary *samples = [source freshSamplesAtUptime:101];
    uint64_t speed = GVMEncodeSample(samples[@"speed"][@"value"], [samples[@"speed"][@"receivedAt"] doubleValue]);
    uint64_t limit = GVMEncodeSample(samples[@"speedLimit"][@"value"], [samples[@"speedLimit"][@"receivedAt"] doubleValue]);
    Require([GVMDecodeSample(speed, 101, YES) isEqual:@0], @"real stationary zero survives transport");
    Require([GVMDecodeSample(limit, 101, NO) isEqual:@50], @"real limit survives transport");
    Require(!GVMDecodeSample(speed, 105, YES), @"sample expires at five seconds");
    Require(!GVMDecodeSample(limit, 99, NO), @"future samples rejected");
    [source applyArguments:@[@{@"speedLimit":@60}, @NO] receivedAt:104];
    samples = [source freshSamplesAtUptime:104];
    uint64_t heartbeatSpeed = GVMEncodeSample(samples[@"speed"][@"value"], [samples[@"speed"][@"receivedAt"] doubleValue]);
    Require(heartbeatSpeed == speed, @"limit and heartbeat do not renew speed timestamp");
    samples = [source freshSamplesAtUptime:106];
    Require(!samples[@"speed"] && [samples[@"speedLimit"][@"value"] isEqual:@60], @"fields expire independently");
    [source applyArguments:@[@{@"speedLimit":NSNull.null}, @NO] receivedAt:106];
    Require(![source freshSamplesAtUptime:106][@"speedLimit"], @"explicit null clears limit");
    Require(!GVMEncodeSample(@YES, 1) && !GVMEncodeSample(@401, 1) && !GVMEncodeSample(@1.5, 1), @"invalid samples rejected");
    Require(!GVMDecodeSample(0, 1, YES), @"missing state rejected");
    Require(!GVMDecodeSample(GVMEncodeSample(@0, 1), 1, NO), @"zero limit unavailable");
    Require([GVMDecodeSample(GVMEncodeSample(@400, 1000.125), 1000.126, YES) isEqual:@400], @"maximum valid value and fractional uptime");
    puts("speed-state tests passed");
} return 0; }
