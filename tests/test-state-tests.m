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
        NSDictionary *lanes=GVMParseTestLanes(@"1,1,x1,5,4@127");
        assert([lanes[@"distance"] isEqual:@127] && [lanes[@"items"] count]==5 && [lanes[@"items"][2][@"enabled"] isEqual:@NO]);
        NSDictionary *decoded=GVMDecodeTestLanes(GVMEncodeTestLanes(lanes[@"items"],lanes[@"distance"]));
        assert([decoded isEqual:lanes]);
        NSDictionary *every=GVMParseTestLanes(@"85,257,81,69,68,21,17");
        assert(every[@"distance"]==NSNull.null && [GVMDecodeTestLanes(GVMEncodeTestLanes(every[@"items"],NSNull.null)) isEqual:every]);
        for (NSString *bad in @[@"",@"1,,4",@"1,512",@"1,a",@"1@",@"1@-5",@"1@10001x",@"1,1,1,1,1,1,1,1",@"1@2@3"])
            assert(!GVMParseTestLanes(bad));
        assert(!GVMParseTestLanes(@"1@10001"));
        // Speed limit signs per lane: every lane or none.
        NSDictionary *limited=GVMParseTestLanes(@"1:90,5:70,0:0,4:-60");
        assert([[limited[@"items"] valueForKey:@"limit"] isEqual:(@[@90,@70,@0,@-60])] && [limited[@"items"][1][@"code"] isEqual:@5]);
        assert([GVMDecodeTestLaneLimits(GVMEncodeTestLaneLimits(limited[@"items"]),4) isEqual:(@[@90,@70,@0,@-60])]);
        assert([GVMDecodeTestLaneLimits(GVMEncodeTestLaneLimits(GVMParseTestLanes(@"0:-1,0:255,0:-255")[@"items"]),3) isEqual:(@[@-1,@255,@-255])]);
        for (NSString *bad in @[@"1:90,5",@"1:256",@"1:-256",@"1:9a",@"1:",@"1:90:80",@"1:--5"]) assert(!GVMParseTestLanes(bad));
        assert(!GVMEncodeTestLaneLimits(GVMParseTestLanes(@"1,5")[@"items"]) && !GVMDecodeTestLaneLimits(0,2));
        assert(!GVMDecodeTestLaneLimits(GVMEncodeTestLaneLimits(limited[@"items"]),3) && !GVMDecodeTestLaneLimits(1ULL<<63,8));
        assert(!GVMDecodeTestLanes(0) && !GVMDecodeTestLanes(GVMEncodeTestLanes(@[@{@"code":@1}],@5)|(1ULL<<40)));
        puts("test-state tests passed");
    }
}
