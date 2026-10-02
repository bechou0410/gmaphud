#import <Foundation/Foundation.h>
#import "test-state.h"
#include <assert.h>
#include <math.h>

int main(void) {
    @autoreleasepool {
        for (NSNumber *speed in @[@0, @40, @50, @60, @400]) {
            uint64_t state = GVMEncodeTest(speed.integerValue, 50, 100, 60);
            NSDictionary *value = GVMDecodeTest(state, 100);
            assert([value[@"speed"] isEqual:speed]);
            assert([value[@"limit"] isEqual:@50]);
            assert(GVMDecodeTest(state, 159.999));
            assert(!GVMDecodeTest(state, 160));
        }
        assert(!GVMDecodeTest(0, 100));
        assert(!GVMDecodeTest(GVMEncodeTest(60, 50, 100, 300), 99));
        assert(!GVMDecodeTest(GVMEncodeTest(60, 50, 100, 60), NAN));
        assert(!GVMEncodeTest(-1, 50, 100, 60));
        assert(!GVMEncodeTest(401, 50, 100, 60));
        assert(!GVMEncodeTest(60, 0, 100, 60));
        assert(!GVMEncodeTest(60, 401, 100, 60));
        assert(!GVMEncodeTest(60, 50, 100, 0));
        assert(!GVMEncodeTest(60, 50, 100, 301));
        assert(!GVMEncodeTest(60, 50, INFINITY, 60));
        assert(!GVMDecodeTest((200000ULL << 18) | (50ULL << 9) | 511, 100));
        puts("test-state tests passed");
    }
}
