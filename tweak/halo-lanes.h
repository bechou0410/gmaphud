#import <UIKit/UIKit.h>

// The New UI lane strip, drawn as a QCVN lane sign: one white arrow per lane, left to right, on a
// blue panel with dashed white lane lines, and under each arrow the lane's speed limit sign when the
// source gives one (alone when it gives limits without arrows). Lanes in effect have no distance
// tag; lanes announced ahead carry one across the panel's bottom edge, filling as the junction gets
// closer. Drawn at size L and scaled by `scale`, so its frame is
// GVMLaneStripMetricsFor(count, GVMLaneStripOptionsFor(lanes)) times `scale`.
@interface GVMHaloLaneStrip : UIView
// The source output's lanes sample: {distance, items:[{code, enabled, limit}], receivedAt}.
@property(nonatomic,copy) NSDictionary *lanes;
@property(nonatomic) double scale;
// Set when the layout found room for the arrows but not for the limit row under them.
@property(nonatomic) BOOL withoutLimits;
@end
