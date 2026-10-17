#import <UIKit/UIKit.h>

// The New UI lane strip, drawn as a QCVN lane sign: one white arrow per lane, left to right, on a
// blue panel with dashed white lane lines. Lanes in effect have no distance tag; lanes announced
// ahead carry one across the panel's bottom edge, filling as the junction gets closer. Drawn at size
// L and scaled by `scale`, so its frame is GVMLaneStripMetricsFor(count, tagged) times `scale`.
@interface GVMHaloLaneStrip : UIView
// The source output's lanes sample: {distance, items:[{code, enabled}], receivedAt}.
@property(nonatomic,copy) NSDictionary *lanes;
@property(nonatomic) double scale;
@end
