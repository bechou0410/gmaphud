#import <Foundation/Foundation.h>

// Copy only speed fields from VietMap's [patch, replaceAll] method arguments.
NSArray *VMNavCopyOverlayArguments(id arguments);

// Access only from one serial queue. Each field retains its own sample age.
@interface VMNavSource : NSObject
- (void)applyMainSpeedLimit:(id)value receivedAt:(NSTimeInterval)received;
// VietMap's main-channel current speed (km/h). The overlay only flows while VietMap's CarPlay channel
// is live, so on an iPhone without CarPlay this is the only speed there is.
- (void)applyMainSpeed:(id)value receivedAt:(NSTimeInterval)received;
- (void)applyArguments:(id)arguments receivedAt:(NSTimeInterval)received;
- (NSDictionary *)freshSamplesAtUptime:(NSTimeInterval)uptime;
- (NSDictionary *)payloadAtUptime:(NSTimeInterval)uptime timestamp:(NSTimeInterval)timestamp;
@end
