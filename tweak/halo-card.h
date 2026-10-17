#import "speed-card.h"

// The Halo bubble: a round speed dial with a progress ring, the limit badge pinned to it, the
// source tag below it and up to two alert signs with distance tags. Drawn on the
// speed-presentation canvas, so the same view serves CarPlay, the iPhone overlay and the
// settings preview.
@interface GVMHaloSpeedCard : UIView <GVMSpeedCardView>
@property(nonatomic) BOOL test, stacked, trailing;
// The large circle is the speed limit sign and the small one the current speed (Settings: Vòng lớn).
@property(nonatomic) BOOL limitDial;
@end
