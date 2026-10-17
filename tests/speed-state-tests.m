#import "speed-state.h"
#import "nav-source.h"

static void Require(BOOL condition, NSString *name) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", name.UTF8String); exit(1); }
}

int main(void) { @autoreleasepool {
    Require(GVMShouldRequestSource(10,-1,YES,NO,YES), @"first missing-data request");
    Require(!GVMShouldRequestSource(11,10,YES,NO,YES), @"requests throttled");
    Require(GVMShouldRequestSource(12,10,YES,NO,YES), @"request repeats after two seconds");
    Require(!GVMShouldRequestSource(12,10,NO,NO,YES), @"hidden map does not request");
    Require(!GVMShouldRequestSource(12,10,YES,YES,YES), @"test mode does not request");
    Require(!GVMShouldRequestSource(12,10,YES,NO,NO), @"fresh data does not request");
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
    VMNavSource *patchSource=[VMNavSource new];
    [patchSource applyArguments:@[@{@"speed":@42,@"speedLimit":@50},@YES] receivedAt:100];
    [patchSource applyArguments:@[@{},@NO] receivedAt:104];
    Require(![patchSource freshSamplesAtUptime:105][@"speedLimit"], @"empty patches cannot refresh a limit");
    [patchSource applyArguments:@[@{@"speed":@0},@NO] receivedAt:106];
    Require([patchSource freshSamplesAtUptime:106][@"speed"] && ![patchSource freshSamplesAtUptime:106][@"speedLimit"], @"stationary speed cannot renew an old limit");
    [patchSource applyArguments:@[@{@"speed":@YES},@NO] receivedAt:107];
    Require(![patchSource freshSamplesAtUptime:107][@"speed"], @"boolean clears valid speed rather than showing one");
    [patchSource applyArguments:@[@{@"speed":@23},@NO] receivedAt:106];
    Require(![patchSource freshSamplesAtUptime:107][@"speed"], @"late updates cannot restore invalidated state");
    VMNavSource *mainSource=[VMNavSource new];
    [mainSource applyArguments:@[@{@"speed":@42},@NO] receivedAt:100];
    [mainSource applyMainSpeedLimit:@50 receivedAt:101];
    Require([[mainSource freshSamplesAtUptime:101][@"speedLimit"][@"value"] isEqual:@50], @"main limit accepted");
    Require(![mainSource freshSamplesAtUptime:105][@"speed"], @"main limit does not renew speed");
    Require(![mainSource freshSamplesAtUptime:106][@"speedLimit"], @"main limit expires");
    [mainSource applyMainSpeedLimit:@60 receivedAt:107];
    [mainSource applyMainSpeedLimit:@0 receivedAt:108];
    Require(![mainSource freshSamplesAtUptime:108][@"speedLimit"], @"zero main limit clears sign");
    [mainSource applyMainSpeedLimit:@80 receivedAt:107];
    Require(![mainSource freshSamplesAtUptime:108][@"speedLimit"], @"old main limit cannot replace newer invalidation");
    [mainSource applyMainSpeedLimit:@"50" receivedAt:109];
    Require(![mainSource freshSamplesAtUptime:109][@"speedLimit"], @"string main limit rejected");
    // iPhone without CarPlay: VietMap's overlay never runs, the main channel carries speed and limit.
    VMNavSource *phoneOnly=[VMNavSource new];
    [phoneOnly applyMainSpeedLimit:@50 receivedAt:200];
    [phoneOnly applyMainSpeed:@37.6 receivedAt:201];
    Require([[phoneOnly freshSamplesAtUptime:202][@"speed"][@"value"] isEqual:@38] &&
        [[phoneOnly freshSamplesAtUptime:202][@"speedLimit"][@"value"] isEqual:@50], @"main-channel speed shows without the overlay");
    [phoneOnly applyMainSpeed:@0 receivedAt:203];
    Require([[phoneOnly freshSamplesAtUptime:203][@"speed"][@"value"] isEqual:@0], @"stopped is a speed");
    [phoneOnly applyMainSpeed:@"fast" receivedAt:204];
    Require(![phoneOnly freshSamplesAtUptime:204][@"speed"], @"a non-number clears the speed");
    [phoneOnly applyMainSpeed:@44 receivedAt:205];
    Require(![phoneOnly freshSamplesAtUptime:211][@"speed"], @"main-channel speed expires like the overlay's");
    puts("speed-state tests passed");
} return 0; }
