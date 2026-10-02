#import <Foundation/Foundation.h>

// Caller supplies monotonic sample age, separate from the wire's Unix timestamp.
NSDictionary *VMNavPayload(NSDictionary *sample, NSTimeInterval age, NSTimeInterval timestamp);
