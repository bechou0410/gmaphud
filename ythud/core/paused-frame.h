#import <AVFoundation/AVFoundation.h>

@interface YTAVPausedFrame : NSObject
@property(nonatomic, readonly) CALayer *layer;
@property(nonatomic, readonly) BOOL frozen;
- (BOOL)captureFromLayer:(AVPlayerLayer *)source;
- (void)updateFromLayer:(AVPlayerLayer *)source mediaTime:(double)time;
@end
