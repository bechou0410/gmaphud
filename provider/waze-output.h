#import "source-output.h"

// A GPS speed shown below this counts as stationary; it is held for at most this long, awake or
// asleep.
static const long GVMWazeStationaryKmh=3;
static const double GVMWazeStationaryHoldSeconds=600;

// Main-queue owned. Native identities remain private to this adapter.
@interface GVMWazeOutputStore : NSObject
- (void)updateIdentifier:(NSString *)identifier icon:(NSString *)icon type:(NSInteger)type
                subtype:(NSInteger)subtype trait:(NSInteger)trait distance:(NSInteger)distance
                valid:(BOOL)valid passed:(BOOL)passed
               atUptime:(NSTimeInterval)uptime;
- (void)updateSpeed:(double)millimetresPerSecond timestamp:(double)timestamp
               now:(double)now uptime:(double)uptime optionalLimit:(uint64_t)limit;
// Live native limit read at uptime; replaces or clears only the limit field.
- (void)updateLimit:(uint64_t)limit uptime:(double)uptime;
// While the latest GPS sample was stationary, keeps its speed fresh at uptime (wall time now):
// iOS delivers a stationary background app GPS only every few seconds to minutes (over four
// minutes indoors), and the next movement brings new samples. A moving speed still lapses five
// seconds after its sample. A newer sample that arrives late ends the hold.
- (void)holdStationarySpeedAtUptime:(double)uptime now:(double)now;
// Ends the hold, for a GPS run that stopped; the speed then lapses as usual.
- (void)endStationaryHold;
// Receive uptime of the latest accepted GPS sample, or -1. A held speed does not change it.
@property (nonatomic, readonly) double lastSampleUptime;
- (NSDictionary *)outputAtUptime:(NSTimeInterval)uptime;
@end
