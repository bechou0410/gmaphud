#import <Foundation/Foundation.h>
#import "speed-presentation.h"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        assert(GVMWarningFor(@44,@50)==GVMWarningNormal);
        assert(GVMWarningFor(@45,@50)==GVMWarningNear);
        assert(GVMWarningFor(@50,@50)==GVMWarningNear);
        assert(GVMWarningFor(@51,@50)==GVMWarningOver);
        assert(GVMWarningFor(@25,@30)==GVMWarningNear);
        assert(GVMWarningFor(@0,@50)==GVMWarningNormal);
        assert(GVMWarningFor(nil,@50)==GVMWarningNormal);
        assert(GVMWarningFor(@60,nil)==GVMWarningNormal);
        assert(GVMWarningFor(@60,@0)==GVMWarningNormal);
        assert(GVMProgressFor(@0,@50)==0);
        assert(GVMProgressFor(@25,@50)==0.5);
        assert(GVMProgressFor(@60,@50)==1);
        assert(GVMProgressFor(nil,@50)==0);
        assert(GVMProgressFor(@60,nil)==0);
        puts("speed-presentation tests passed");
    }
}
