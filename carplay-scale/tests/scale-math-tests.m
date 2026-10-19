#import "scale-math.h"
#include <math.h>

static int failures;
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); failures++; }
}
static BOOL Near(CGFloat a, CGFloat b) { return fabs(a - b) < 1e-6; }

int main(void) {
    @autoreleasepool {
        Check(Near(CPSRatioFromPreferences(nil, nil), 0.8), "fresh install uses the default 80%");
        Check(Near(CPSRatioFromPreferences(@YES, @70), 0.7), "a listed percent is used");
        Check(CPSRatioFromPreferences(@NO, @70) == 0, "the switch turns scaling off");
        Check(Near(CPSRatioFromPreferences(@YES, @65), 0.8), "an unlisted percent falls back to the default");
        Check(Near(CPSRatioFromPreferences(@YES, (NSNumber *)@"70"), 0.8), "a non-number percent falls back to the default");
        Check(Near(CPSRatioFromPreferences((NSNumber *)@"NO", @90), 0.9), "a non-number switch counts as on");

        // Standard 800x480 head unit drawn at 2x (400x240 points).
        CPSScaledMode standard = CPSMakeScaledMode(CGSizeMake(800, 480), 2, 0.8);
        Check(standard.valid && Near(standard.scale, 1.6), "800x480 at 80% draws at 1.6x");
        Check(Near(standard.pointSize.width, 500) && Near(standard.pointSize.height, 300), "800x480 at 80% gains 500x300 points");

        // Minimum 748x456 (374x228 points): the width is rounded to whole points, as measured on the device.
        CPSScaledMode minimum = CPSMakeScaledMode(CGSizeMake(748, 456), 2, 0.8);
        Check(minimum.valid && Near(minimum.pointSize.width, 468), "width rounds to whole points");
        Check(Near(minimum.scale, 748.0 / 468) && Near(minimum.pointSize.height, 456 / (748.0 / 468)), "scale keeps the pixel size");

        // Wide head units chosen at 3x by CarKit keep the same relative shrink.
        CPSScaledMode wide = CPSMakeScaledMode(CGSizeMake(1920, 720), 3, 0.8);
        Check(wide.valid && Near(wide.scale, 2.4) && Near(wide.pointSize.width, 800) && Near(wide.pointSize.height, 300), "1920x720 at 3x and 80%");

        Check(!CPSMakeScaledMode(CGSizeMake(800, 480), 2, 0).valid, "ratio 0 means unchanged");
        Check(!CPSMakeScaledMode(CGSizeMake(800, 480), 2, 1).valid, "ratio 1 means unchanged");
        Check(!CPSMakeScaledMode(CGSizeMake(0, 480), 2, 0.8).valid, "empty pixel size is rejected");
        Check(!CPSMakeScaledMode(CGSizeMake(800, 480), 0, 0.8).valid, "zero native scale is rejected");
        Check(!CPSMakeScaledMode(CGSizeMake(NAN, 480), 2, 0.8).valid, "non-finite size is rejected");
        Check(!CPSMakeScaledMode(CGSizeMake(800, 480), 2, INFINITY).valid, "non-finite ratio is rejected");
        Check(!CPSMakeScaledMode(CGSizeMake(800, 480), 1e-320, 0.8).valid, "a width that overflows is rejected");

        // 1920x720 at 70% gave apps 913.9999999999999 points before neighbouring whole widths were tried.
        CPSScaledMode wide70 = CPSMakeScaledMode(CGSizeMake(1920, 720), 3, 0.7);
        Check(wide70.valid && 1920 / wide70.scale == wide70.pointSize.width, "1920x720 at 70% gives apps an exact whole width");

        // 800x480 at 90% gave 479 pixel rows on the device before the height was nudged.
        CGSize screens[] = {{800, 480}, {748, 456}, {1280, 720}, {1920, 720}, {900, 1200}, {1024, 600}, {960, 540}};
        CGFloat scales[] = {2, 2, 3, 3, 2, 2, 2};
        for (NSUInteger s = 0; s < sizeof screens / sizeof screens[0]; s++)
            for (NSUInteger i = 0; i < CPSPercentChoiceCount; i++) {
                CPSScaledMode mode = CPSMakeScaledMode(screens[s], scales[s], CPSPercentChoices[i] / 100.0);
                CGFloat target = scales[s] * CPSPercentChoices[i] / 100.0;
                Check(mode.valid && mode.scale < scales[s] && fabs(mode.scale - target) < target * 0.01, "every offered size draws within 1% of its target scale");
                Check(floor(mode.pointSize.width * mode.scale) == screens[s].width, "points x scale keeps every pixel column");
                Check(floor(mode.pointSize.height * mode.scale) == screens[s].height, "points x scale keeps every pixel row");
                Check(mode.pointSize.width == floor(mode.pointSize.width) && screens[s].width / mode.scale >= mode.pointSize.width, "apps get back a whole point width");
            }
    }
    if (failures) return 1;
    puts("scale-math-tests: all passed");
    return 0;
}
