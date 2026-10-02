#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, GVMWarning) { GVMWarningNormal, GVMWarningNear, GVMWarningOver };
GVMWarning GVMWarningFor(NSNumber *speed, NSNumber *limit);
double GVMProgressFor(NSNumber *speed, NSNumber *limit);
