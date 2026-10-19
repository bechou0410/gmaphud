#import <Foundation/Foundation.h>
NSDictionary *GVMVietMapOutputAlert(NSDictionary *alert, NSTimeInterval receivedAt);
// Entries marked active are signs VietMap shows as in effect (its sticky alerts). They carry no
// distance, so upcoming signs take the two alert places first, and a sign that is also upcoming is
// shown once, with its distance.
NSDictionary *GVMVietMapOutput(NSDictionary *samples, NSArray<NSDictionary *> *alertEntries, NSTimeInterval now);
// The lane sample for the source output. While VietMap counts down to a junction (updateLaneInfo,
// `advance` = {distance, items}), its lanes show early with that distance. Otherwise the lanes VietMap
// Live shows (its overlay's laneInfo, `codes`) are in effect on the stretch being driven: no distance,
// and VietMap changes or clears them itself; an overlay patch without laneInfo leaves them as they
// are. Its per-lane speed limits (`limits`, laneSpeedLimits) go with those lanes when they count the
// same lanes, or stand alone, on lanes without a direction, when there are no arrows, as VietMap's
// own panel does. The sample carries the publication time `now`, so it stays fresh only while VietMap
// Live keeps publishing. nil when there are none.
NSDictionary *GVMVietMapLaneSample(NSDictionary *advance, NSArray<NSNumber *> *codes, NSArray<NSNumber *> *limits,
    NSTimeInterval now);
// How long an advance countdown counts without a new updateLaneInfo (VietMap sends one about every
// two seconds and clears it at the junction).
extern const NSTimeInterval GVMVietMapAdvanceLaneLifetime;
