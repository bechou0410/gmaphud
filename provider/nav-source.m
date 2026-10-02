#import "nav-source.h"
#import "nav-payload.h"
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>

NSArray *VMNavCopyOverlayArguments(id arguments) {
    if (![arguments isKindOfClass:NSArray.class] || [arguments count] != 2) return nil;
    id patch = arguments[0], replace = arguments[1];
    if (![patch isKindOfClass:NSDictionary.class] || ![replace isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)replace) != CFBooleanGetTypeID()) return nil;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"speed", @"speedLimit"]) {
        id value = patch[key];
        if (value) fields[key] = [value isKindOfClass:NSNumber.class] ? [value copy] : NSNull.null;
    }
    return @[[fields copy], replace];
}

@implementation VMNavSource {
    NSMutableDictionary *_values;
    NSMutableDictionary *_times;
    NSTimeInterval _lastUpdate;
    BOOL _hasUpdate;
}

- (instancetype)init {
    if ((self = [super init])) {
        _values = [NSMutableDictionary dictionary];
        _times = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)applyArguments:(id)arguments receivedAt:(NSTimeInterval)received {
    NSArray *update = VMNavCopyOverlayArguments(arguments);
    if (!update || !isfinite(received) || received < 0 || (_hasUpdate && received < _lastUpdate)) return;
    _hasUpdate = YES;
    _lastUpdate = received;
    if ([update[1] boolValue]) {
        [_values removeAllObjects];
        [_times removeAllObjects];
    }
    NSDictionary *fields = update[0];
    for (NSString *key in fields) {
        _values[key] = fields[key];
        _times[key] = @(received);
    }
}

- (NSDictionary *)payloadAtUptime:(NSTimeInterval)uptime timestamp:(NSTimeInterval)timestamp {
    NSMutableDictionary *payload = [VMNavPayload(nil, INFINITY, timestamp) mutableCopy];
    NSDictionary *samples = [self freshSamplesAtUptime:uptime];
    for (NSString *key in samples) {
        NSString *wireKey = [key isEqualToString:@"speed"] ? @"currentSpeed" : @"speedLimit";
        payload[wireKey] = samples[key][@"value"];
    }
    return payload;
}

- (NSDictionary *)freshSamplesAtUptime:(NSTimeInterval)uptime {
    NSMutableDictionary *samples = [NSMutableDictionary dictionary];
    for (NSString *key in _values) {
        // Reuse numeric and age validation separately for each source field.
        NSDictionary *field = VMNavPayload(@{key: _values[key]}, uptime - [_times[key] doubleValue], 0);
        NSString *wireKey = [key isEqualToString:@"speed"] ? @"currentSpeed" : @"speedLimit";
        if (field[wireKey]) samples[key] = @{@"value":field[wireKey], @"receivedAt":_times[key]};
    }
    return [samples copy];
}
@end
