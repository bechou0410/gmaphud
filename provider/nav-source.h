#import <Foundation/Foundation.h>

// Copy only speed fields from VietMap's [patch, replaceAll] method arguments.
NSArray *VMNavCopyOverlayArguments(id arguments);

// Access only from one serial queue. Each field retains its own sample age.
@interface VMNavSource : NSObject
- (void)applyArguments:(id)arguments receivedAt:(NSTimeInterval)received;
- (NSDictionary *)freshSamplesAtUptime:(NSTimeInterval)uptime;
- (NSDictionary *)payloadAtUptime:(NSTimeInterval)uptime timestamp:(NSTimeInterval)timestamp;
@end
