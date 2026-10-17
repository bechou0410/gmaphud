#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// Main-thread only. Shares the existing player, never constructs another one.
void YTAVObserveDedicatedOutput(id backend, AVPlayer *player, AVPlayerLayer *originalLayer, UIView *originalView, BOOL activeInPool);
void YTAVTickDedicatedOutput(void);
void YTAVStopDedicatedOutput(NSString *reason);
void YTAVShutdownDedicatedOutput(void);

void YTAVSelectedOutputBackendChanged(id previousBackend, id selectedBackend);
