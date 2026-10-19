#import <Foundation/Foundation.h>
#include <stdint.h>

extern const char *const GVMTestStateName;
uint64_t GVMEncodeTest(NSInteger speed, NSInteger limit, NSTimeInterval uptime, NSInteger seconds);
NSDictionary *GVMDecodeTest(uint64_t state, NSTimeInterval uptime);

// Test lanes shown with a test sample: up to seven lanes, each {code: VietMap lane bitmask,
// enabled: BOOL}, and a distance in metres or NSNull. They never enter the live source namespace.
extern const char *const GVMTestLaneStateName;
uint64_t GVMEncodeTestLanes(NSArray<NSDictionary *> *items, id distance);
NSDictionary *GVMDecodeTestLanes(uint64_t state);
// Their speed limit signs, when the test gives every lane one, as VietMap gives them: a limit in
// km/h, 0 or -1 for a sign without a number, -2 or less for a grey one. 0 when there are none.
extern const char *const GVMTestLaneLimitStateName;
uint64_t GVMEncodeTestLaneLimits(NSArray<NSDictionary *> *items);
NSArray<NSNumber *> *GVMDecodeTestLaneLimits(uint64_t state, NSUInteger count);
// Parses "1,1,1,5,4@127": comma-separated lane codes, an x prefix for a lane not to use, then an
// optional @ and distance. A lane may add ":LIMIT" (-255 to 255), every lane or none: "1:90,5:-70".
// nil when malformed.
NSDictionary *GVMParseTestLanes(NSString *text);
