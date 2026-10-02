#import "speed-presentation.h"
GVMWarning GVMWarningFor(NSNumber *speed, NSNumber *limit) {
    if (!speed || !limit || limit.doubleValue <= 0) return GVMWarningNormal;
    if (speed.doubleValue > limit.doubleValue) return GVMWarningOver;
    return speed.doubleValue >= MAX(0, limit.doubleValue - 5) ? GVMWarningNear : GVMWarningNormal;
}
double GVMProgressFor(NSNumber *speed, NSNumber *limit) {
    if (!speed || !limit || limit.doubleValue <= 0) return 0;
    return MIN(1, MAX(0, speed.doubleValue / limit.doubleValue));
}
