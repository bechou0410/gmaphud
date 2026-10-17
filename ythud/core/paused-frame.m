#import "paused-frame.h"
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation YTAVPausedFrame {
    CIContext *_imageContext;
    double _lastTime, _lastMovement, _lastCapture;
}
- (instancetype)init {
    if ((self = [super init])) {
        _layer = [CALayer layer]; _layer.hidden = YES;
        _layer.contentsGravity = kCAGravityResizeAspect;
        _layer.backgroundColor = UIColor.blackColor.CGColor;
        _lastTime = NAN; _lastMovement = CACurrentMediaTime();
    }
    return self;
}
- (BOOL)frozen { return !_layer.hidden; }
- (BOOL)captureFromLayer:(AVPlayerLayer *)source {
    SEL selector = sel_registerName("copyDisplayedPixelBuffer");
    Method method = source ? class_getInstanceMethod(source.class, selector) : NULL;
    if (!method || strcmp(method_getTypeEncoding(method), "^{__CVBuffer=}16@0:8")) return NO;
    CVPixelBufferRef buffer = ((CVPixelBufferRef (*)(id,SEL))objc_msgSend)(source, selector);
    if (!buffer) return NO;
    @try {
        if (!_imageContext) _imageContext = [CIContext contextWithOptions:nil];
        CIImage *image = [CIImage imageWithCVPixelBuffer:buffer];
        CGRect bounds = image.extent;
        if (bounds.size.width > 0 && bounds.size.height > 0 && !CGRectIsInfinite(bounds)) {
            CGFloat scale = MIN(1, MIN(960 / bounds.size.width, 540 / bounds.size.height));
            image = [image imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
            CGImageRef frame = [_imageContext createCGImage:image fromRect:image.extent];
            if (frame) { _layer.contents = (__bridge id)frame; CGImageRelease(frame); }
        }
    } @finally { CVPixelBufferRelease(buffer); }
    return _layer.contents != nil;
}
- (void)updateFromLayer:(AVPlayerLayer *)source mediaTime:(double)time {
    double now = CACurrentMediaTime();
    if (isfinite(time) && (!isfinite(_lastTime) || fabs(time - _lastTime) > .01)) _lastMovement = now;
    BOOL paused = now - _lastMovement >= .6;
    if ((!paused && now - _lastCapture >= .5) || (paused && _layer.hidden)) {
        [self captureFromLayer:source]; _lastCapture = now;
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _layer.hidden = !paused || !_layer.contents;
    [CATransaction commit];
    _lastTime = time;
}
@end
