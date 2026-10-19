#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Preference domain shared by the Settings pane and the CarPlay hook, and the Darwin notification posted on change.
#define CPS_PREFERENCES_DOMAIN "com.chou.carplayscale"
#define CPS_CHANGED_NOTIFICATION "com.chou.carplayscale/changed"
// Count of CarPlay launches that scaled the screen but did not run long enough to be trusted; Settings clears it.
#define CPS_UNCONFIRMED_LAUNCHES_KEY "unconfirmedLaunches"

// Interface sizes offered in Settings, in percent of the native CarPlay size.
extern const NSInteger CPSPercentChoices[];
extern const NSUInteger CPSPercentChoiceCount;
extern const NSInteger CPSPercentDefault;

// Ratio the saved preferences ask for: 0 when the switch is off, otherwise the chosen percent / 100.
// A missing switch means on; a missing or unknown percent means the default.
CGFloat CPSRatioFromPreferences(NSNumber *enabled, NSNumber *percent);

typedef struct {
    BOOL valid;
    CGSize pointSize;  // Point size of the scaled screen. The width is a whole number of points that apps
                       // get back exactly when possible; points x scale never falls below the pixel size.
    CGFloat scale;     // Pixels per point, below the native scale.
} CPSScaledMode;

// Keeps the pixel size and divides the native point scale by the ratio, so the screen gains points.
// Invalid for non-finite or non-positive input and for a ratio outside (0, 1).
CPSScaledMode CPSMakeScaledMode(CGSize pixelSize, CGFloat nativeScale, CGFloat ratio);
