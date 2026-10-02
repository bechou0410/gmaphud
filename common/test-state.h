#import <Foundation/Foundation.h>
#include <stdint.h>

extern const char *const GVMTestStateName;
uint64_t GVMEncodeTest(NSInteger speed, NSInteger limit, NSTimeInterval uptime, NSInteger seconds);
NSDictionary *GVMDecodeTest(uint64_t state, NSTimeInterval uptime);
